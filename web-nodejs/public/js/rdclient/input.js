/**
 * BetterDesk Web Remote Client - Input Manager
 * Captures keyboard and mouse events and converts them to RustDesk protocol messages
 */

/* global RDProtocol */

// eslint-disable-next-line no-unused-vars
class RDInput {
    /**
     * @param {HTMLCanvasElement} canvas - The canvas element to capture events from
     * @param {RDRenderer} renderer - Renderer for coordinate mapping
     * @param {Function} sendMessage - Callback to send protocol messages
     */
    constructor(canvas, renderer, sendMessage) {
        /** @type {HTMLCanvasElement} */
        this.canvas = canvas;
        /** @type {RDRenderer} */
        this.renderer = renderer;
        /** @type {Function} */
        this.sendMessage = sendMessage;

        /** @type {boolean} */
        this.enabled = false;
        /** @type {boolean} Pointer lock active */
        this.pointerLocked = false;
        /** @type {Set<string>} Currently pressed keys */
        this.pressedKeys = new Set();
        /** @type {number} Mouse button state bitmask */
        this.buttonMask = 0;

        // Mouse move throttling (~60 Hz for smoother remote control)
        this._lastMouseSendTime = 0;
        this._mouseThrottleMs = 16;

        // Bound event handlers (for removal)
        this._onMouseMove = this._handleMouseMove.bind(this);
        this._onMouseDown = this._handleMouseDown.bind(this);
        this._onMouseUp = this._handleMouseUp.bind(this);
        this._onWheel = this._handleWheel.bind(this);
        this._onKeyDown = this._handleKeyDown.bind(this);
        this._onKeyUp = this._handleKeyUp.bind(this);
        this._onContextMenu = (e) => e.preventDefault();
        this._onPointerLockChange = this._handlePointerLockChange.bind(this);
    }

    /**
     * Start capturing input events
     */
    start() {
        if (this.enabled) return;

        const c = this.canvas;
        c.addEventListener('mousemove', this._onMouseMove);
        c.addEventListener('mousedown', this._onMouseDown);
        c.addEventListener('mouseup', this._onMouseUp);
        c.addEventListener('wheel', this._onWheel, { passive: false });
        c.addEventListener('contextmenu', this._onContextMenu);

        // Keyboard events on document (canvas needs focus for key events)
        document.addEventListener('keydown', this._onKeyDown);
        document.addEventListener('keyup', this._onKeyUp);

        // Pointer Lock change detection
        document.addEventListener('pointerlockchange', this._onPointerLockChange);

        // Make canvas focusable
        c.tabIndex = 0;
        c.focus();

        this.enabled = true;
    }

    /**
     * Stop capturing input events
     */
    stop() {
        if (!this.enabled) return;

        const c = this.canvas;
        c.removeEventListener('mousemove', this._onMouseMove);
        c.removeEventListener('mousedown', this._onMouseDown);
        c.removeEventListener('mouseup', this._onMouseUp);
        c.removeEventListener('wheel', this._onWheel);
        c.removeEventListener('contextmenu', this._onContextMenu);

        document.removeEventListener('keydown', this._onKeyDown);
        document.removeEventListener('keyup', this._onKeyUp);
        document.removeEventListener('pointerlockchange', this._onPointerLockChange);

        if (this.pointerLocked) {
            document.exitPointerLock();
        }

        this.pressedKeys.clear();
        this.buttonMask = 0;
        this.enabled = false;
    }

    /**
     * Request pointer lock for better mouse capture
     */
    requestPointerLock() {
        this.canvas.requestPointerLock();
    }

    /**
     * Release pointer lock
     */
    exitPointerLock() {
        if (this.pointerLocked) {
            document.exitPointerLock();
        }
    }

    // ---- Mouse Event Handlers ----

    /**
     * RustDesk mouse button mask values:
     * 1 = left button press
     * 2 = left button release
     * 4 = right button press
     * 8 = right button release
     * 16 = middle button press
     * 32 = middle button release
     * 64 = scroll up
     * 128 = scroll down
     * 256 = scroll left
     * 512 = scroll right
     * MOVE = 0 (just position update)
     */

    _handleMouseMove(e) {
        if (!this.enabled) return;

        // Throttle mouse moves to reduce bandwidth and improve responsiveness
        const now = performance.now();
        if (now - this._lastMouseSendTime < this._mouseThrottleMs) return;
        this._lastMouseSendTime = now;

        const pos = this._getRemotePosition(e);
        if (!pos) return;

        // Mouse move = mask 0
        this.sendMessage({
            mouseEvent: {
                mask: 0,
                x: pos.x,
                y: pos.y,
                modifiers: this._getModifiers(e)
            }
        });
    }

    _handleMouseDown(e) {
        if (!this.enabled) return;
        e.preventDefault();

        // Focus canvas for keyboard events
        this.canvas.focus();

        const pos = this._getRemotePosition(e);
        if (!pos) return;

        let mask = 0;
        switch (e.button) {
        case 0: mask = 1; break;   // Left press
        case 1: mask = 16; break;  // Middle press
        case 2: mask = 4; break;   // Right press
        }

        if (mask) {
            this.buttonMask |= mask;
            this.sendMessage({
                mouseEvent: {
                    mask: mask,
                    x: pos.x,
                    y: pos.y,
                    modifiers: this._getModifiers(e)
                }
            });
        }
    }

    _handleMouseUp(e) {
        if (!this.enabled) return;
        e.preventDefault();

        const pos = this._getRemotePosition(e);
        if (!pos) return;

        let mask = 0;
        switch (e.button) {
        case 0: mask = 2; break;   // Left release
        case 1: mask = 32; break;  // Middle release
        case 2: mask = 8; break;   // Right release
        }

        if (mask) {
            this.buttonMask &= ~mask;
            this.sendMessage({
                mouseEvent: {
                    mask: mask,
                    x: pos.x,
                    y: pos.y,
                    modifiers: this._getModifiers(e)
                }
            });
        }
    }

    _handleWheel(e) {
        if (!this.enabled) return;
        e.preventDefault();

        const pos = this._getRemotePosition(e);
        if (!pos) return;

        let mask = 0;
        if (e.deltaY < 0) mask = 64;       // Scroll up
        else if (e.deltaY > 0) mask = 128;  // Scroll down
        else if (e.deltaX < 0) mask = 256;  // Scroll left
        else if (e.deltaX > 0) mask = 512;  // Scroll right

        if (mask) {
            this.sendMessage({
                mouseEvent: {
                    mask: mask,
                    x: pos.x,
                    y: pos.y,
                    modifiers: this._getModifiers(e)
                }
            });
        }
    }

    // ---- Keyboard Event Handlers ----

    /**
     * Map browser key code to RustDesk ControlKey enum value
     */
    static KEY_MAP = {
        'Escape': 'Escape',
        'Backspace': 'Backspace',
        'Tab': 'Tab',
        'Enter': 'Return',
        'ShiftLeft': 'Shift',
        'ShiftRight': 'RShift',
        'ControlLeft': 'Control',
        'ControlRight': 'RControl',
        'AltLeft': 'Alt',
        'AltRight': 'RAlt',
        'MetaLeft': 'Meta',
        'MetaRight': 'RWin',
        'Pause': 'Pause',
        'CapsLock': 'CapsLock',
        'Space': 'Space',
        'PageUp': 'PageUp',
        'PageDown': 'PageDown',
        'End': 'End',
        'Home': 'Home',
        'ArrowLeft': 'LeftArrow',
        'ArrowUp': 'UpArrow',
        'ArrowRight': 'RightArrow',
        'ArrowDown': 'DownArrow',
        'PrintScreen': 'Snapshot',
        'Insert': 'Insert',
        'Delete': 'Delete',
        'ScrollLock': 'Scroll',
        'NumLock': 'NumLock',
        'F1': 'F1', 'F2': 'F2', 'F3': 'F3', 'F4': 'F4',
        'F5': 'F5', 'F6': 'F6', 'F7': 'F7', 'F8': 'F8',
        'F9': 'F9', 'F10': 'F10', 'F11': 'F11', 'F12': 'F12',
        'Numpad0': 'Numpad0', 'Numpad1': 'Numpad1', 'Numpad2': 'Numpad2',
        'Numpad3': 'Numpad3', 'Numpad4': 'Numpad4', 'Numpad5': 'Numpad5',
        'Numpad6': 'Numpad6', 'Numpad7': 'Numpad7', 'Numpad8': 'Numpad8',
        'Numpad9': 'Numpad9',
        'NumpadMultiply': 'Multiply',
        'NumpadAdd': 'Add',
        'NumpadSubtract': 'Subtract',
        'NumpadDecimal': 'Decimal',
        'NumpadDivide': 'Divide',
        'NumpadEnter': 'NumpadEnter',
        'ContextMenu': 'Apps',
        'AudioVolumeMute': 'VolumeMute',
        'AudioVolumeDown': 'VolumeDown',
        'AudioVolumeUp': 'VolumeUp'
    };

    _handleKeyDown(e) {
        if (!this.enabled) return;
        // Don't capture if focus is on an input element
        if (this._isInputFocused()) return;

        e.preventDefault();
        e.stopPropagation();

        const keyCode = e.code;
        if (this.pressedKeys.has(keyCode)) return; // Key repeat
        this.pressedKeys.add(keyCode);

        const controlKey = RDInput.KEY_MAP[keyCode];

        if (controlKey) {
            // Special key
            this.sendMessage({
                keyEvent: {
                    controlKey: controlKey,
                    down: true,
                    press: false,
                    modifiers: this._getKeyModifiers(e),
                    mode: 'Legacy'
                }
            });
        } else if (e.key.length === 1) {
            // Character key - send as chr (unicode code point)
            this.sendMessage({
                keyEvent: {
                    chr: e.key.charCodeAt(0),
                    down: true,
                    press: true,
                    modifiers: this._getKeyModifiers(e),
                    mode: 'Legacy'
                }
            });
        }
    }

    _handleKeyUp(e) {
        if (!this.enabled) return;
        if (this._isInputFocused()) return;

        e.preventDefault();
        e.stopPropagation();

        const keyCode = e.code;
        this.pressedKeys.delete(keyCode);

        const controlKey = RDInput.KEY_MAP[keyCode];

        if (controlKey) {
            this.sendMessage({
                keyEvent: {
                    controlKey: controlKey,
                    down: false,
                    press: false,
                    modifiers: this._getKeyModifiers(e),
                    mode: 'Legacy'
                }
            });
        } else if (e.key.length === 1) {
            this.sendMessage({
                keyEvent: {
                    chr: e.key.charCodeAt(0),
                    down: false,
                    press: false,
                    modifiers: this._getKeyModifiers(e),
                    mode: 'Legacy'
                }
            });
        }
    }

    // ---- Helpers ----

    _handlePointerLockChange() {
        this.pointerLocked = document.pointerLockElement === this.canvas;
    }

    /**
     * Get remote coordinates from mouse event
     * @param {MouseEvent} e
     * @returns {{ x: number, y: number }|null}
     */
    _getRemotePosition(e) {
        const rect = this.canvas.getBoundingClientRect();
        const canvasX = e.clientX - rect.left;
        const canvasY = e.clientY - rect.top;

        const pos = this.renderer.canvasToRemote(canvasX, canvasY);

        // Clamp to remote display bounds
        if (pos.x < 0 || pos.y < 0 ||
            pos.x > this.renderer.remoteWidth ||
            pos.y > this.renderer.remoteHeight) {
            return null;
        }

        return pos;
    }

    /**
     * Get mouse modifier flags
     * @param {MouseEvent} e
     * @returns {number[]}
     */
    _getModifiers(e) {
        // Values must match ControlKey enum in message.proto:
        // Alt=1, Control=4, Meta=23, Shift=29
        const mods = [];
        if (e.shiftKey) mods.push(29);  // ControlKey.Shift
        if (e.ctrlKey) mods.push(4);    // ControlKey.Control
        if (e.altKey) mods.push(1);     // ControlKey.Alt
        if (e.metaKey) mods.push(23);   // ControlKey.Meta
        return mods;
    }

    /**
     * Get keyboard modifier flags
     * @param {KeyboardEvent} e
     * @returns {number[]}
     */
    _getKeyModifiers(e) {
        return this._getModifiers(e);
    }

    /**
     * Check if an input-like element has focus
     * @returns {boolean}
     */
    _isInputFocused() {
        const tag = document.activeElement?.tagName?.toLowerCase();
        return tag === 'input' || tag === 'textarea' || tag === 'select';
    }

    /**
     * Close and release all resources
     */
    close() {
        this.stop();
    }
}

window.RDInput = RDInput;
