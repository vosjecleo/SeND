//! Read-only Megolm notification decryption. No Olm device/account mutations.
use vodozemac::megolm::{ExportedSessionKey, InboundGroupSession, MegolmMessage, SessionConfig};
use wasm_bindgen::prelude::*;

fn decrypt(key: &str, ciphertext: &str, session_id: &str, room_id: &str) -> Result<String, ()> {
    if key.len() > 1024 || ciphertext.len() > 128 * 1024 {
        return Err(());
    }
    let key = ExportedSessionKey::from_base64(key).map_err(|_| ())?;
    let mut session = InboundGroupSession::import(&key, SessionConfig::version_1());
    if session.session_id() != session_id {
        return Err(());
    }
    let message = MegolmMessage::from_base64(ciphertext).map_err(|_| ())?;
    let decrypted = session.decrypt(&message).map_err(|_| ())?;
    let json: serde_json::Value = serde_json::from_slice(&decrypted.plaintext).map_err(|_| ())?;
    if json["room_id"].as_str() != Some(room_id) {
        return Err(());
    }
    // Include the authenticated index for notification-specific replay checks.
    Ok(serde_json::json!({"event": json, "index": decrypted.message_index}).to_string())
}

#[wasm_bindgen]
pub fn decrypt_notification(
    key: &str,
    ciphertext: &str,
    session_id: &str,
    room_id: &str,
) -> Result<String, JsValue> {
    decrypt(key, ciphertext, session_id, room_id)
        .map_err(|_| JsValue::from_str("Preview unavailable"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use vodozemac::megolm::GroupSession;

    #[test]
    fn decrypts_real_megolm_and_rejects_wrong_context() {
        let mut outbound = GroupSession::new(SessionConfig::version_1());
        let inbound = InboundGroupSession::new(&outbound.session_key(), SessionConfig::version_1());
        let key = inbound.export_at_first_known_index().to_base64();
        let encrypted = outbound.encrypt(r#"{"room_id":"!room:test","type":"m.room.message","content":{"body":"Hello","msgtype":"m.text"}}"#).to_base64();
        let id = outbound.session_id();
        let output = decrypt(&key, &encrypted, &id, "!room:test").unwrap();
        assert!(output.contains("Hello"));
        assert!(decrypt(&key, &encrypted, "wrong", "!room:test").is_err());
        assert!(decrypt(&key, &encrypted, &id, "!other:test").is_err());
        assert!(decrypt(&key, "bad ciphertext", &id, "!room:test").is_err());
    }
}
