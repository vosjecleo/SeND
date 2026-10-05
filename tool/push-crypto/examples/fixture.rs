// Synthetic integration fixture only: no real accounts, credentials or keys.
use vodozemac::megolm::{GroupSession, InboundGroupSession, SessionConfig};
fn main() {
    let mut outbound = GroupSession::new(SessionConfig::version_1());
    let inbound = InboundGroupSession::new(&outbound.session_key(), SessionConfig::version_1());
    let ciphertext = outbound.encrypt(r#"{"room_id":"!room:test","type":"m.room.message","content":{"body":"Hello from encrypted push","msgtype":"m.text"}}"#).to_base64();
    println!(
        "{}",
        serde_json::json!({"key": inbound.export_at_first_known_index().to_base64(),
        "id": outbound.session_id(), "ciphertext": ciphertext})
    );
}
