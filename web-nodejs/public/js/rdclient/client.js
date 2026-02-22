/**
 * BetterDesk Web Remote Client - Main Client Orchestrator
 * Ties together all rdclient modules: connection, protocol, crypto,
 * video, audio, renderer, and input.
 *
 * Usage:
 *   const client = new RDClient(canvas, { deviceId: 'ABC123' });
 *   client.on('state', (state) => updateUI(state));
 *   await client.connect();
 *   // user enters password...
 *   await client.authenticate(password);
 *   // ...session runs...
 *   client.disconnect();
 */

/* global RDConnection, RDProtocol, RDCrypto, RDVideo, RDAudio, RDRenderer, RDInput */

// eslint-disable-next-line no-unused-vars
class RDClient {
    /**
     * @param {HTMLCanvasElement} canvas
     * @param {Object} opts
     * @param {string} opts.deviceId - Target device ID
     * @param {boolean} [opts.disableAudio=false]
     * @param {number} [opts.fps=30]
     * @param {string} [opts.scaleMode='fit']
     */
    constructor(canvas, opts = {}) {
        if (!canvas) throw new Error('Canvas element required');
        if (!opts.deviceId) throw new Error('deviceId required');

        this.deviceId = opts.deviceId;
        this.opts = opts;

        // Sub-modules
        this.conn = new RDConnection();
        this.proto = new RDProtocol();
        this.crypto = new RDCrypto();
        this.video = new RDVideo();
        this.audio = new RDAudio();
        this.renderer = new RDRenderer(canvas);
        this.input = new RDInput(canvas, this.renderer, (msg) => this._sendPeerMessage(msg));

        // State
        this._state = 'idle'; // idle | connecting | waiting_password | authenticating | streaming | disconnected | error
        this._listeners = {};
        this._peerInfo = null;
        this._loginChallenge = null;
        this._pingInterval = null;
        this._statsInterval = null;

        // Stream decoders for RustDesk variable-length frame codec (TCP reassembly)
        this._rendezvousDecoder = null;
        this._relayDecoder = null;

        // Settings
        this.renderer.setScaleMode(opts.scaleMode || 'fit');
    }

    get state() { return this._state; }
    get peerInfo() { return this._peerInfo; }

    // ---- Event Emitter ----

    on(event, fn) {
        if (!this._listeners[event]) this._listeners[event] = [];
        this._listeners[event].push(fn);
        return this;
    }

    off(event, fn) {
        const arr = this._listeners[event];
        if (arr) this._listeners[event] = arr.filter(f => f !== fn);
        return this;
    }

    _emit(event, ...args) {
        const arr = this._listeners[event];
        if (arr) arr.forEach(fn => { try { fn(...args); } catch(e) { console.error(e); } });
    }

    // ---- Main Connection Flow ----

    /**
     * Start connection to remote device
     * Flow: load proto → rendezvous → punch hole → relay → wait for SignedId → key exchange → encrypted session
     *
     * RustDesk handshake (after relay pairing):
     *   1. Target sends SignedId (unencrypted, signed with Ed25519)
     *   2. We verify, extract target's ephemeral Curve25519 pk
     *   3. We generate keypair + symmetric key, encrypt symkey with NaCl box
     *   4. We send PublicKey { our_pk, encrypted_symkey }
     *   5. Target decrypts symkey, enables encryption
     *   6. Target sends Hash (encrypted) - password challenge
     *   7. We decrypt, show password prompt
     */
    async connect() {
        try {
            this._setState('connecting');
            this._emit('log', 'Loading protocol definitions...');

            // Step 1: Load protobuf definitions
            await this.proto.load();

            // Step 2: Check WebCodecs support (non-blocking, fallback available)
            if (!RDVideo.isSupported()) {
                this._emit('log', 'WebCodecs unavailable, using software fallback');
            }

            // Step 3: Create stream decoders for TCP frame reassembly
            this._rendezvousDecoder = this.proto.createStreamDecoder();
            this._relayDecoder = this.proto.createStreamDecoder();

            // Step 4: Connect to rendezvous server via WS proxy
            this._emit('log', 'Connecting to rendezvous server...');
            await this.conn.connectRendezvous();

            // Step 5: Send PunchHoleRequest (with server public key for licence validation)
            this._emit('log', `Requesting connection to ${this.deviceId}...`);
            const punchHole = this.proto.buildPunchHoleRequest(this.deviceId, this.opts.serverPubKey);
            const punchData = this.proto.encodeRendezvous(punchHole);
            this.conn.sendRendezvous(punchData);

            // Step 6: Wait for PunchHoleResponse / RelayResponse from hbbs
            const rendezvousResponse = await this._waitForRendezvousResponse();

            if (rendezvousResponse.error) {
                throw new Error(`Connection refused: ${rendezvousResponse.error}`);
            }

            // Store peer's server-signed pk for SignedId verification (from RelayResponse.pk)
            this._peerSignedPk = rendezvousResponse.pk || null;

            // Step 7: Close rendezvous, connect to relay
            this.conn.closeRendezvous();

            this._emit('log', 'Connecting to relay server...');
            await this.conn.connectRelay();

            // Step 8: Setup relay message handler BEFORE sending anything
            this.conn.on('relay:message', (data) => this._handleRelayData(data));
            this.conn.on('relay:close', () => {
                if (this._state !== 'disconnected' && this._state !== 'error') {
                    this._handleDisconnect('Relay connection closed');
                }
            });
            this.conn.on('relay:error', (e) => this._handleDisconnect('Relay error: ' + e.message));

            // Step 9: Send RequestRelay to hbbr (with licence_key - hbbr validates this!)
            this._emit('log', `Requesting relay (uuid: ${(rendezvousResponse.uuid || '').substring(0, 8)}...)...`);
            const requestRelay = this.proto.buildRequestRelay(
                this.deviceId,
                rendezvousResponse.uuid || '',
                rendezvousResponse.relayServer || '',
                this.opts.serverPubKey
            );
            const relayData = this.proto.encodeRendezvous(requestRelay);
            this.conn.sendRelay(relayData);

            // Step 10: Wait for target's SignedId (first message from relay)
            // Target sends SignedId FIRST (unencrypted, signed with their Ed25519 key).
            // We do NOT send anything until we process SignedId and perform key exchange.
            this._emit('log', 'Waiting for peer handshake...');
            this._setState('waiting_password');

        } catch (err) {
            this._handleError(err);
        }
    }

    /**
     * Authenticate with password
     * @param {string} password
     */
    async authenticate(password) {
        try {
            this._setState('authenticating');
            this._emit('log', 'Authenticating...');

            // Hash the password
            const challenge = this._loginChallenge || '';
            const salt = this._loginSalt || '';
            console.log('[RDClient] Auth: challenge=' + JSON.stringify(challenge).substring(0, 80)
                + ' salt=' + JSON.stringify(salt) + ' passLen=' + password.length);

            const hash = await this.crypto.hashPassword(password, salt, challenge);
            console.log('[RDClient] Auth: hash=' + Array.from(hash.slice(0, 8)).map(b => b.toString(16).padStart(2, '0')).join('')
                + '... (' + hash.length + ' bytes)');

            // Build and send LoginRequest
            // username must be set to target device ID (RustDesk validates: is_ip || is_domain_port || == Config::get_id())
            const loginReq = this.proto.buildLoginRequest(hash, {
                username: this.deviceId,
                myId: 'betterdesk-web-' + Date.now().toString(36),
                myName: 'BetterDesk Web',
                disableAudio: this.opts.disableAudio || false,
                fps: this.opts.fps || 30
            });

            console.log('[RDClient] Auth: sending LoginRequest, crypto.enabled=' + this.crypto.enabled
                + ' sendSeq=' + this.crypto._sendSeq + ' relayWsState=' + (this.conn.relayWs?.readyState));
            this._sendPeerMessage(loginReq);
            console.log('[RDClient] Auth: LoginRequest sent, sendSeq now=' + this.crypto._sendSeq);

            // The response will be handled in _handleRelayMessage

        } catch (err) {
            this._handleError(err);
        }
    }

    /**
     * Disconnect from remote device
     */
    disconnect() {
        this._cleanup();
        this._setState('disconnected');
        this._emit('log', 'Disconnected');
    }

    // ---- Message Handling ----

    /**
     * Wait for rendezvous server response (PunchHoleResponse or RelayResponse)
     * 
     * Flow: After PunchHoleRequest, hbbs either:
     * - Sends PunchHoleResponse(failure) immediately if target not found/offline
     * - Forwards PunchHole to target peer, then later forwards RelayResponse 
     *   (from target peer) back to us through the same TCP connection
     * 
     * @returns {Promise<Object>}
     */
    _waitForRendezvousResponse() {
        return new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                this.conn.off('rendezvous:message', handler);
                reject(new Error('Rendezvous response timeout (30s) - target device may be offline'));
            }, 30000);

            const handler = (rawData) => {
                // Decode frames from raw TCP data via stream decoder
                const frames = this._rendezvousDecoder.feed(rawData);
                if (frames.length === 0) return; // Incomplete frame, wait for more data

                clearTimeout(timeout);
                this.conn.off('rendezvous:message', handler);

                try {
                    // Process first complete frame
                    const msg = this.proto.decodeRendezvous(frames[0]);

                    if (msg.punchHoleResponse) {
                        const resp = msg.punchHoleResponse;
                        console.log('[RDClient] PunchHoleResponse:', JSON.stringify({
                            failure: resp.failure,
                            relayServer: resp.relayServer,
                            otherFailure: resp.otherFailure,
                            hasSocketAddr: !!(resp.socketAddr && resp.socketAddr.length),
                            hasPk: !!(resp.pk && resp.pk.length),
                            natType: resp.natType
                        }));
                        // Check for failure:
                        // Proto3 default enum = 0 (ID_NOT_EXIST), so we check if we got
                        // a relay server or socket_addr to determine success
                        const hasRelay = resp.relayServer && resp.relayServer.length > 0;
                        const hasSocket = resp.socketAddr && resp.socketAddr.length > 0;

                        if (hasRelay || hasSocket) {
                            // Successful response
                            resolve({
                                relayServer: resp.relayServer || '',
                                uuid: resp.uuid || '',
                                pk: resp.pk || null,
                                natType: resp.natType
                            });
                        } else {
                            // Failure - map enum values from PunchHoleResponse.Failure
                            const failureNames = {
                                0: 'Device not found',     // ID_NOT_EXIST
                                2: 'Device offline',       // OFFLINE
                                3: 'License mismatch',     // LICENSE_MISMATCH
                                4: 'Too many connections'  // LICENSE_OVERUSE
                            };
                            const reason = resp.otherFailure
                                || failureNames[resp.failure]
                                || `Unknown error (code: ${resp.failure})`;
                            resolve({ error: reason });
                        }
                    } else if (msg.relayResponse) {
                        const rr = msg.relayResponse;
                        console.log('[RDClient] RelayResponse from hbbs:', JSON.stringify({
                            relayServer: rr.relayServer || '',
                            uuid: (rr.uuid || '').substring(0, 8) + '...',
                            id: rr.id || '',
                            hasPk: !!(rr.pk && rr.pk.length),
                            refuseReason: rr.refuseReason || ''
                        }));
                        if (rr.refuseReason && rr.refuseReason.length > 0) {
                            resolve({ error: 'Relay refused: ' + rr.refuseReason });
                        } else {
                            resolve({
                                relayServer: rr.relayServer || '',
                                uuid: rr.uuid || '',
                                pk: rr.pk || null,
                                id: rr.id || ''
                            });
                        }
                    } else {
                        resolve({ error: 'Unexpected rendezvous response' });
                    }
                } catch (err) {
                    reject(err);
                }
            };

            this.conn.on('rendezvous:message', handler);
        });
    }

    /**
     * Handle raw incoming relay data (TCP chunks via WebSocket)
     * Uses stream decoder for frame reassembly, then dispatches each complete message.
     * After hbbr pairs both peers (by UUID), it operates in raw mode - just bridging
     * TCP bytes between the two connections. All frames are peer-to-peer Messages.
     * @param {ArrayBuffer} rawData
     */
    _handleRelayData(rawData) {
        try {
            const frames = this._relayDecoder.feed(rawData);
            for (const frame of frames) {
                this._handleRelayMessage(frame);
            }
        } catch (err) {
            console.warn('[RDClient] Error decoding relay data:', err.message);
        }
    }

    /**
     * Handle a single decoded relay frame (protobuf bytes)
     * After relay is established, all messages are peer-to-peer Message protocol.
     * hbbr acts as a transparent byte bridge and does NOT send any messages of its own.
     * @param {Uint8Array} frameData - Raw protobuf bytes (frame header already stripped)
     */
    _handleRelayMessage(frameData) {
        try {
            let data = frameData;

            // Decrypt if encryption is active
            if (this.crypto.enabled) {
                data = this.crypto.processIncoming(data);
                if (!data) {
                    console.warn('[RDClient] Decryption failed at recvSeq=' + this.crypto._recvSeq);
                    return;
                }
            }

            const msg = this.proto.decodeMessage(data);
            this._dispatchMessage(msg);

        } catch (err) {
            console.warn('[RDClient] Error handling relay message:', err.message, err.stack);
        }
    }

    /**
     * Dispatch decoded peer message to appropriate handler
     * @param {Object} msg - Decoded protobuf Message
     */
    _dispatchMessage(msg) {
        // Hash challenge (before login)
        if (msg.hash) {
            this._loginChallenge = msg.hash.challenge || '';
            this._loginSalt = msg.hash.salt || '';
            this._emit('log', 'Password required');
            this._setState('waiting_password');
            this._emit('password_required');
            return;
        }

        // Login response
        if (msg.loginResponse) {
            this._handleLoginResponse(msg.loginResponse);
            return;
        }

        // Video frame
        if (msg.videoFrame) {
            this._handleVideoFrame(msg.videoFrame);
            return;
        }

        // Audio frame
        if (msg.audioFrame) {
            this._handleAudioFrame(msg.audioFrame);
            return;
        }

        // Cursor data (cursor image)
        if (msg.cursorData) {
            this.renderer.updateCursor(msg.cursorData);
            return;
        }

        // Cursor position
        if (msg.cursorPosition) {
            this.renderer.updateCursorPosition(msg.cursorPosition);
            return;
        }

        // Cursor ID (predefined cursor)
        if (msg.cursorId) {
            this._emit('cursor_id', msg.cursorId);
            return;
        }

        // Clipboard
        if (msg.clipboard) {
            this._handleClipboard(msg.clipboard);
            return;
        }

        // Test delay (ping/pong)
        if (msg.testDelay) {
            this._handleTestDelay(msg.testDelay);
            return;
        }

        // Misc messages
        if (msg.misc) {
            this._handleMisc(msg.misc);
            return;
        }

        // Audio format
        if (msg.audioFormat) {
            this.audio.configure({
                sampleRate: msg.audioFormat.sampleRate || 48000,
                channels: msg.audioFormat.channels || 2
            });
            return;
        }

        // Peer info
        if (msg.peerInfo) {
            this._handlePeerInfo(msg.peerInfo);
            return;
        }

        // Public key from peer
        if (msg.publicKey) {
            this._handlePeerPublicKey(msg.publicKey);
            return;
        }

        // Signed ID from peer
        if (msg.signedId) {
            this._handleSignedId(msg.signedId);
            return;
        }
    }

    // ---- Specific Message Handlers ----

    _handlePeerPublicKey(pk) {
        // This handler is for the case where the peer sends PublicKey
        // (non-standard flow). In standard RustDesk flow, the target
        // sends SignedId first, and WE send PublicKey back.
        console.log('[RDClient] Received unexpected PublicKey from peer');
    }

    /**
     * Handle SignedId from target peer.
     * SignedId.id = 64-byte Ed25519 signature + protobuf(IdPk{ id, pk })
     * where pk is the target's EPHEMERAL Curve25519 public key.
     *
     * After extracting the key, we perform NaCl box key exchange:
     * 1. Generate our ephemeral Curve25519 keypair
     * 2. Generate random 32-byte symmetric key
     * 3. Encrypt symmetric key: nacl.box(symKey, zeroNonce, theirPk, ourSk)
     * 4. Send PublicKey { ourPk, encryptedSymKey }
     * 5. Enable counter-based secretbox encryption with symKey
     */
    _handleSignedId(signedId) {
        const idBytes = signedId.id;
        if (!idBytes || idBytes.length === 0) {
            this._emit('log', 'Received empty SignedId');
            return;
        }

        // Parse SignedId: extract target's ephemeral Curve25519 pk
        const parsed = this.crypto.parseSignedId(
            new Uint8Array(idBytes),
            this.proto.types.IdPk
        );

        if (!parsed) {
            this._emit('log', 'Failed to parse SignedId');
            return;
        }

        this._emit('log', `Peer identified: ${parsed.peerId}`);
        console.log('[RDClient] Peer ephemeral pk:', parsed.peerPk.length, 'bytes');

        // Step 1: Generate our ephemeral Curve25519 keypair + symmetric key
        this.crypto.generateKeyPair();
        this.crypto.generateSymmetricKey();

        // Step 2: Create encrypted key exchange message
        // nacl.box(symKey, zeroNonce, theirPk, ourSk) → sealed (48 bytes)
        const keyMsg = this.crypto.createSymmetricKeyMsg(parsed.peerPk);

        // Step 3: Send PublicKey with our ephemeral pk + box-encrypted symmetric key
        const pkMsg = this.proto.buildPublicKey(
            keyMsg.asymmetricValue,  // our ephemeral Curve25519 pk (32 bytes)
            keyMsg.symmetricValue    // box-encrypted symmetric key (48 bytes)
        );
        this._sendPeerMessage(pkMsg);

        // Step 4: Enable counter-based encryption (both counters start at 0)
        // From now on, all incoming messages are encrypted by the target
        // and all our outgoing messages will be encrypted
        this.crypto.enable();
        this._emit('log', 'Encryption enabled, waiting for password challenge...');
    }

    _handleLoginResponse(resp) {
        console.log('[RDClient] LoginResponse:', JSON.stringify(resp, (k, v) => {
            if (v && v.type === 'Buffer') return '<Buffer>';
            if (v instanceof Uint8Array) return '<bytes:' + v.length + '>';
            return v;
        }).substring(0, 500));

        if (resp.error && resp.error.length > 0) {
            console.log('[RDClient] Login error: ' + resp.error);
            this._emit('login_error', resp.error);
            this._setState('waiting_password');
            return;
        }

        // Login successful
        this._peerInfo = resp.peerInfo || null;
        console.log('[RDClient] Login successful, peerInfo:', this._peerInfo ? 'present' : 'null');
        this._emit('log', 'Login successful');
        this._emit('login_success', resp);
        this._startSession();
    }

    _handlePeerInfo(info) {
        this._peerInfo = info;
        this._emit('peer_info', info);

        // If we got peer info without hash challenge, session can start
        if (this._state === 'waiting_password') {
            // Some devices don't require password
            this._emit('log', 'No password required');
            this._startSession();
        }
    }

    async _handleVideoFrame(videoFrame) {
        // Track total video frames from peer for diagnostics
        this._peerFrameCount = (this._peerFrameCount || 0) + 1;
        if (this._peerFrameCount <= 3 || this._peerFrameCount % 100 === 0) {
            console.log('[RDClient] VideoFrame #' + this._peerFrameCount + ' from peer');
        }

        // Send video_received ack so the peer knows we are consuming frames
        // Without this, RustDesk server throttles down to 1-5 FPS
        this._sendPeerMessage(this.proto.buildMisc('videoReceived', true));

        const codec = this.proto.detectVideoCodec(videoFrame);
        if (!codec || codec === 'rgb' || codec === 'yuv') return;

        // Initialize video decoder if needed
        if (!this.video.initialized || this.video.currentCodec !== codec) {
            try {
                await this.video.init(codec);
                this._emit('log', `Video codec: ${codec.toUpperCase()}`);
            } catch (err) {
                this._emit('log', `Video codec ${codec} not supported: ${err.message}`);
                return;
            }
        }

        // Decode each encoded frame
        const frames = this.proto.getEncodedFrames(videoFrame);
        for (const frame of frames) {
            await this.video.decode(frame);
        }
    }

    _handleAudioFrame(audioFrame) {
        if (audioFrame.data) {
            this.audio.play({
                data: audioFrame.data,
                timestamp: audioFrame.timestamp || 0
            });
        }
    }

    _handleClipboard(clipboard) {
        if (clipboard.content) {
            const decoder = new TextDecoder();
            const text = decoder.decode(clipboard.content);
            this._emit('clipboard', text);

            // Copy to local clipboard if permitted
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).catch(() => {
                    // Clipboard write permission denied - ignore
                });
            }
        }
    }

    _handleTestDelay(testDelay) {
        if (!testDelay.fromClient) {
            // Respond to server's ping
            const pong = this.proto.buildTestDelay();
            this._sendPeerMessage(pong);
        } else {
            // Our ping came back - calculate RTT
            const rtt = Date.now() - (testDelay.time || 0);
            this._emit('latency', rtt);
        }
    }

    _handleMisc(misc) {
        if (misc.closeReason) {
            this._handleDisconnect('Remote: ' + misc.closeReason);
            return;
        }
        if (misc.chatMessage) {
            this._emit('chat', misc.chatMessage.text || '');
            return;
        }
        if (misc.option) {
            this._emit('option', misc.option);
            return;
        }
        if (misc.permissionInfo) {
            this._emit('permission', misc.permissionInfo);
            return;
        }
        if (misc.switchDisplay) {
            this._emit('switch_display', misc.switchDisplay);
            return;
        }
    }

    // ---- Session Management ----

    /**
     * Start the streaming session after successful login
     */
    _startSession() {
        this._setState('streaming');
        this.conn.setConnected();

        // Initialize video decoder callbacks
        this.video.onFrame = (frame) => this.renderer.pushFrame(frame);
        this.video.onError = (err) => this._emit('log', 'Video error: ' + err.message);

        // Start render loop
        this.renderer.startRenderLoop();

        // Start input capture
        this.input.start();

        // Initialize audio (will actually start on first audio data)
        if (!this.opts.disableAudio && RDAudio.isSupported()) {
            this.audio.init().catch(() => {
                this._emit('log', 'Audio init failed');
            });
        }

        // Start ping interval
        this._pingInterval = setInterval(() => {
            if (this._state === 'streaming') {
                const ping = this.proto.buildTestDelay();
                this._sendPeerMessage(ping);
            }
        }, 3000);

        // Start stats reporting
        this._statsInterval = setInterval(() => {
            if (this._state === 'streaming') {
                this._emit('stats', this.getStats());
            }
        }, 1000);

        this._emit('session_start');
    }

    // ---- Send Helpers ----

    /**
     * Send a peer-to-peer message through the relay
     * Order: serialize protobuf → encrypt (if enabled) → frame → send
     * @param {Object} msgObj - Message object (will be encoded as Message protobuf)
     */
    _sendPeerMessage(msgObj) {
        if (!this.proto.loaded) return;

        // Step 1: Serialize to raw protobuf bytes (no frame header)
        let data = this.proto.serializeMessage(msgObj);

        // Step 2: Encrypt if enabled (encrypts the raw protobuf)
        if (this.crypto.enabled) {
            data = this.crypto.processOutgoing(data);
        }

        // Step 3: Add frame header to the (possibly encrypted) bytes
        const framed = this.proto.frameBytes(data);

        // Step 4: Send over relay WebSocket
        this.conn.sendRelay(framed);
    }

    // ---- State & Cleanup ----

    _setState(state) {
        if (this._state !== state) {
            const prev = this._state;
            this._state = state;
            this._emit('state', state, prev);
        }
    }

    _handleError(err) {
        console.error('[RDClient]', err);
        this._emit('error', err.message || err);
        this._cleanup();
        this._setState('error');
    }

    _handleDisconnect(reason) {
        this._emit('log', `Disconnected: ${reason}`);
        this._cleanup();
        this._setState('disconnected');
        this._emit('disconnected', reason);
    }

    _cleanup() {
        if (this._pingInterval) {
            clearInterval(this._pingInterval);
            this._pingInterval = null;
        }
        if (this._statsInterval) {
            clearInterval(this._statsInterval);
            this._statsInterval = null;
        }

        this.input.stop();
        this.renderer.stopRenderLoop();
        this.video.close();
        this.audio.close();
        this.conn.close();
    }

    // ---- Public Utility Methods ----

    /**
     * Send clipboard text to remote
     * @param {string} text
     */
    sendClipboard(text) {
        if (this._state !== 'streaming') return;
        const msg = this.proto.buildClipboard(text);
        this._sendPeerMessage(msg);
    }

    /**
     * Send Ctrl+Alt+Delete to remote
     */
    sendCtrlAltDel() {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage({
            keyEvent: { controlKey: 'CtrlAltDel', down: true, press: true, modifiers: [], mode: 'Legacy' }
        });
    }

    /**
     * Send Lock Screen command to remote
     */
    sendLockScreen() {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage({
            keyEvent: { controlKey: 'LockScreen', down: true, press: true, modifiers: [], mode: 'Legacy' }
        });
    }

    /**
     * Request screen refresh (force new keyframe)
     */
    sendRefreshScreen() {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildMisc('refreshVideo', true));
    }

    /**
     * Request remote device restart
     */
    sendRestartRemoteDevice() {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildMisc('restartRemoteDevice', true));
    }

    /**
     * Send chat message to remote peer
     * @param {string} text
     */
    sendChat(text) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildChatMessage(text));
    }

    /**
     * Change image quality during session
     * @param {'Best'|'Balanced'|'Low'} quality
     */
    setImageQuality(quality) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildOptionMisc({ imageQuality: quality }));
    }

    /**
     * Change custom FPS during session
     * @param {number} fps
     */
    setCustomFps(fps) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildOptionMisc({ customFps: fps }));
    }

    /**
     * Toggle remote cursor visibility
     * @param {boolean} show
     */
    setShowRemoteCursor(show) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildOptionMisc({ showRemoteCursor: show }));
    }

    /**
     * Toggle input blocking on remote side
     * @param {boolean} block
     */
    setBlockInput(block) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildOptionMisc({ blockInput: block }));
    }

    /**
     * Toggle lock after session end
     * @param {boolean} lock
     */
    setLockAfterSession(lock) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildOptionMisc({ lockAfterSessionEnd: lock }));
    }

    /**
     * Toggle privacy mode on remote
     * @param {boolean} on
     */
    setPrivacyMode(on) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildTogglePrivacyMode(on));
    }

    /**
     * Toggle clipboard sharing
     * @param {boolean} disable
     */
    setDisableClipboard(disable) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildOptionMisc({ disableClipboard: disable }));
    }

    /**
     * Toggle audio on remote side
     * @param {boolean} disable
     */
    setDisableAudio(disable) {
        if (this._state !== 'streaming') return;
        this._sendPeerMessage(this.proto.buildOptionMisc({ disableAudio: disable }));
    }

    /**
     * Toggle view-only mode (local only: disables input capture)
     * @param {boolean} on
     */
    setViewOnly(on) {
        this._viewOnly = on;
        if (on) {
            this.input.stop();
        } else if (this._state === 'streaming') {
            this.input.start();
        }
        this._emit('view_only', on);
    }

    /** @returns {boolean} Whether view-only mode is active */
    get viewOnly() { return this._viewOnly || false; }

    /**
     * Toggle fullscreen
     * @param {HTMLElement} container
     */
    async toggleFullscreen(container) {
        if (document.fullscreenElement) {
            await document.exitFullscreen();
        } else {
            await container.requestFullscreen();
        }
        // Resize after fullscreen change
        setTimeout(() => this.renderer.resize(), 100);
    }

    /**
     * Set scale mode
     * @param {'fit'|'fill'|'1:1'|'stretch'} mode
     */
    setScaleMode(mode) {
        this.renderer.setScaleMode(mode);
        this.opts.scaleMode = mode;
    }

    /**
     * Set audio volume
     * @param {number} volume - 0 to 1
     */
    setVolume(volume) {
        this.audio.setVolume(volume);
    }

    /**
     * Toggle audio mute
     * @param {boolean} muted
     */
    setAudioMuted(muted) {
        this.audio.setMuted(muted);
    }

    /**
     * Get aggregated statistics
     * @returns {Object}
     */
    getStats() {
        return {
            state: this._state,
            video: this.video.getStats(),
            audio: this.audio.getStats(),
            renderer: this.renderer.getStats(),
            connection: this.conn.state
        };
    }
}

window.RDClient = RDClient;
