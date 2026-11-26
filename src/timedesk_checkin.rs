// TimeDesk Host check-in: every 5 minutes, collect a new ID or permanent password that Timelapse staff queued for this
// PC in Timelapse Admin, apply it and report back. The request is signed with this PC's device key; the TimeDesk server
// checks it against the key it already holds for this ID, so only this PC can collect its change.

use hbb_common::{
    bail,
    config::Config,
    log,
    sodiumoxide::crypto::sign,
    tokio::{self, time::sleep},
    ResultType,
};
use serde_json::{json, Value};
use std::time::Duration;

const CHECKIN_URL: &str = "https://timedesk-api.timelapsesoftware.com/checkin";
const CHECKIN_INTERVAL: Duration = Duration::from_secs(300);
/// Shown by TimeDesk Host's home page until the person dismisses it.
pub const NOTICE_OPTION: &str = "timedesk-notice";

#[derive(Debug, PartialEq)]
struct Change {
    cmd: String,
    new_id: String,
    password: String,
    notice: bool,
}

pub fn start() {
    static STARTED: std::sync::Once = std::sync::Once::new();
    STARTED.call_once(|| {
        tokio::spawn(async {
            loop {
                if let Err(err) = check_in().await {
                    hbb_common::throttled_log!(Duration::from_secs(3600), warn, "TimeDesk check-in failed: {err}");
                }
                sleep(CHECKIN_INTERVAL).await;
            }
        });
    });
}

async fn check_in() -> ResultType<()> {
    let Some(change) = post("", "").await? else {
        return Ok(());
    };
    let error = apply(&change).await;
    if error.is_empty() {
        log::info!("TimeDesk check-in: applied change {}", change.cmd);
    } else {
        log::warn!("TimeDesk check-in: change {} failed: {error}", change.cmd);
    }
    post(&change.cmd, &error).await?;
    Ok(())
}

fn signed_message(id: &str, timestamp: &str, result_cmd: &str, result_error: &str) -> String {
    format!("timedesk-checkin\n{id}\n{timestamp}\n{result_cmd}\n{result_error}")
}

/// One signed check-in, reporting the result of the last change if there is one. Retries once with the server's
/// clock when this PC's clock is too far off.
async fn post(result_cmd: &str, result_error: &str) -> ResultType<Option<Change>> {
    let id = Config::get_id();
    let Some(sk) = sign::SecretKey::from_slice(&Config::get_key_pair().0) else {
        bail!("no device key");
    };
    let mut timestamp = (hbb_common::get_time() / 1000).to_string();
    for _ in 0..2 {
        let signature = sign::sign_detached(
            signed_message(&id, &timestamp, result_cmd, result_error).as_bytes(),
            &sk,
        );
        let body = json!({
            "id": &id,
            "timestamp": &timestamp,
            "signature": crate::encode64(signature.to_bytes()),
            "result_cmd": result_cmd,
            "result_error": result_error,
        })
        .to_string();
        let response: Value =
            serde_json::from_str(&crate::post_request(CHECKIN_URL.to_owned(), body, "").await?)?;
        if let Some(server_time) = response["server_time"].as_i64() {
            timestamp = server_time.to_string();
            continue;
        }
        if response.get("error").is_some() {
            bail!("refused: {}", response["error"]);
        }
        return Ok(parse_change(&response));
    }
    bail!("refused: clock")
}

fn parse_change(response: &Value) -> Option<Change> {
    let c = &response["command"];
    let cmd = c["cmd"].as_str().filter(|s| !s.is_empty())?;
    Some(Change {
        cmd: cmd.to_owned(),
        new_id: c["new_id"].as_str().unwrap_or_default().to_owned(),
        password: c["password"].as_str().unwrap_or_default().to_owned(),
        notice: c["notice"].as_bool().unwrap_or(false),
    })
}

/// Applies a change and returns what went wrong, empty on success. Applying it twice is harmless, so a report that
/// didn't arrive just means the server hands the same change over again.
async fn apply(change: &Change) -> String {
    let mut errors = Vec::new();
    if !change.password.is_empty() {
        match crate::ipc::set_permanent_password_with_ack_async(change.password.clone()).await {
            Ok(true) => {}
            Ok(false) => errors.push("the password was refused".to_owned()),
            Err(err) => errors.push(format!("password: {err}")),
        }
    }
    let old_id = Config::get_id();
    if !change.new_id.is_empty() && change.new_id != old_id {
        let res = crate::ui_interface::change_id_shared_(change.new_id.clone(), old_id).await;
        if !res.is_empty() {
            errors.push(format!("ID: {res}"));
        }
    }
    if errors.is_empty() && change.notice {
        Config::set_option(NOTICE_OPTION.to_owned(), notice_text(change));
    }
    errors.join("; ")
}

fn notice_text(change: &Change) -> String {
    match (change.new_id.is_empty(), change.password.is_empty()) {
        (false, false) => format!(
            "Timelapse changed this PC's TimeDesk ID to {} and its permanent password.",
            change.new_id
        ),
        (false, true) => format!("Timelapse changed this PC's TimeDesk ID to {}.", change.new_id),
        _ => "Timelapse changed this PC's TimeDesk permanent password.".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signs_the_same_message_the_server_checks() {
        // timedesk-api/api.py checkin_message()
        assert_eq!(
            signed_message("PCONE1", "1764118800", "c1", ""),
            "timedesk-checkin\nPCONE1\n1764118800\nc1\n"
        );
    }

    #[test]
    fn reads_a_queued_change_and_ignores_none() {
        let queued = json!({"command": {"cmd": "c1", "new_id": "PCNEW1", "password": "Secret123", "notice": true}});
        assert_eq!(
            parse_change(&queued),
            Some(Change {
                cmd: "c1".into(),
                new_id: "PCNEW1".into(),
                password: "Secret123".into(),
                notice: true
            })
        );
        assert_eq!(parse_change(&json!({"command": null})), None);
    }
}
