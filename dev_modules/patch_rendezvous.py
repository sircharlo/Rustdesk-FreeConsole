#!/usr/bin/env python3
"""Patch rendezvous_server.rs to call touch_peer on RegisterPeer"""
import re

with open("rendezvous_server.rs", "r") as f:
    content = f.read()

# Add touch_peer call before creating the response message in update_addr
old = '''let mut msg_out = RendezvousMessage::new();
        msg_out.set_register_peer_response'''

new = '''// Update database status for this peer
        self.pm.touch_peer(&id).await;
        let mut msg_out = RendezvousMessage::new();
        msg_out.set_register_peer_response'''

content = content.replace(old, new)

with open("rendezvous_server.rs", "w") as f:
    f.write(content)

print("Patched rendezvous_server.rs to call touch_peer!")
