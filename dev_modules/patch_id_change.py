#!/usr/bin/env python3
"""Patch rendezvous_server.rs to support ID change via old_id field in RegisterPk"""

with open("rendezvous_server.rs", "r") as f:
    content = f.read()

# Find the RegisterPk handler and add old_id support
old_code = '''                Some(rendezvous_message::Union::RegisterPk(rk)) => {
                    if rk.uuid.is_empty() || rk.pk.is_empty() {
                        return Ok(());
                    }
                    let id = rk.id;'''

new_code = '''                Some(rendezvous_message::Union::RegisterPk(rk)) => {
                    if rk.uuid.is_empty() || rk.pk.is_empty() {
                        return Ok(());
                    }
                    
                    // Handle ID change request (old_id is set)
                    if !rk.old_id.is_empty() {
                        log::info!("ID change request: {} -> {}", rk.old_id, rk.id);
                        
                        // Validate new ID format
                        if rk.id.len() < 6 || rk.id.len() > 16 {
                            log::warn!("ID change rejected: invalid new ID length");
                            return send_rk_res(socket, addr, register_pk_response::Result::INVALID_ID_FORMAT).await;
                        }
                        
                        // Check if new ID already exists
                        if self.pm.is_in_memory(&rk.id).await {
                            log::warn!("ID change rejected: new ID {} already exists", rk.id);
                            return send_rk_res(socket, addr, register_pk_response::Result::ID_EXISTS).await;
                        }
                        
                        // Check if old ID exists and UUID matches
                        if let Some(old_peer) = self.pm.get_in_memory(&rk.old_id).await {
                            let old_uuid = old_peer.read().await.uuid.clone();
                            if old_uuid != rk.uuid {
                                log::warn!("ID change rejected: UUID mismatch for {}", rk.old_id);
                                return send_rk_res(socket, addr, UUID_MISMATCH).await;
                            }
                            
                            // Perform ID change in database
                            match self.pm.db.change_id(&rk.old_id, &rk.id).await {
                                Ok(_) => {
                                    log::info!("ID changed successfully: {} -> {}", rk.old_id, rk.id);
                                    // Remove old peer from memory, it will re-register with new ID
                                    self.pm.remove(&rk.old_id).await;
                                    let mut msg_out = RendezvousMessage::new();
                                    msg_out.set_register_pk_response(RegisterPkResponse {
                                        result: register_pk_response::Result::OK.into(),
                                        ..Default::default()
                                    });
                                    return socket.send(&msg_out, addr).await;
                                }
                                Err(e) => {
                                    log::error!("ID change failed: {}", e);
                                    return send_rk_res(socket, addr, register_pk_response::Result::SERVER_ERROR).await;
                                }
                            }
                        } else {
                            log::warn!("ID change rejected: old ID {} not found", rk.old_id);
                            return send_rk_res(socket, addr, register_pk_response::Result::SERVER_ERROR).await;
                        }
                    }
                    
                    let id = rk.id;'''

if old_code in content:
    content = content.replace(old_code, new_code)
    with open("rendezvous_server.rs", "w") as f:
        f.write(content)
    print("SUCCESS: Patched RegisterPk handler to support ID change")
else:
    print("ERROR: Could not find target code block")
