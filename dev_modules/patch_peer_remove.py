#!/usr/bin/env python3
"""Patch peer.rs to add remove function"""

with open("peer.rs", "r") as f:
    content = f.read()

# Find place to add remove function (after is_in_memory)
marker = '''    #[inline]
    pub(crate) async fn is_in_memory(&self, id: &str) -> bool {
        self.map.read().await.contains_key(id)
    }'''

new_code = '''    #[inline]
    pub(crate) async fn is_in_memory(&self, id: &str) -> bool {
        self.map.read().await.contains_key(id)
    }
    
    /// Remove peer from memory (used during ID change)
    pub(crate) async fn remove(&self, id: &str) {
        self.map.write().await.remove(id);
        log::debug!("Removed peer {} from memory", id);
    }'''

if marker in content:
    content = content.replace(marker, new_code)
    with open("peer.rs", "w") as f:
        f.write(content)
    print("SUCCESS: Added remove function to peer.rs")
else:
    print("ERROR: Could not find target marker in peer.rs")
