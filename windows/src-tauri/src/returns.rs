// The "Chat" page of the SlimIA window: what Claude Code answered, read from the
// conversations it keeps on this computer (`~/.claude/projects/<project>/<session>.jsonl`).
//
// Read only, and only inside that folder: a session is named by its id, which
// must look like one (letters, digits, dashes), never by a path the page sends.
// Only the end of a long file is read, so a conversation of many megabytes
// costs a few hundred kilobytes.

use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::Value;

/// How much of the end of a conversation is read.
const TAIL_BYTES: u64 = 768 * 1024;
/// How much of the start is read to find the first question and the folder.
const HEAD_BYTES: usize = 96 * 1024;
/// Conversations older than this are not listed.
const RECENT: Duration = Duration::from_secs(14 * 24 * 3600);
const MAX_SESSIONS: usize = 40;
/// One entry's text is cut here (a pasted file or a long answer).
const MAX_TEXT: usize = 12_000;

/// A conversation in the list.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SessionInfo {
    pub id: String,
    /// The folder Claude Code was started in, as it wrote it.
    pub cwd: String,
    /// The first thing you asked, shortened.
    pub title: String,
    /// Last write to the conversation, ms since 1970.
    pub updated_at: u64,
}

/// One line of the conversation as the page shows it.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    /// "user", "assistant" or "step" (a tool Claude used).
    pub kind: &'static str,
    pub text: String,
    /// ms since 1970, 0 when the line carries none.
    pub at: u64,
}

fn claude_dir() -> PathBuf {
    match std::env::var_os("CLAUDE_CONFIG_DIR") {
        Some(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => crate::platform::home_dir().join(".claude"),
    }
}

fn projects_dir() -> PathBuf {
    claude_dir().join("projects")
}

/// A session id is a UUID in practice; anything with a separator or a dot is refused.
fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 80 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

fn session_file(id: &str) -> Option<PathBuf> {
    if !valid_id(id) {
        return None;
    }
    let name = format!("{id}.jsonl");
    for project in std::fs::read_dir(projects_dir()).ok()?.flatten() {
        let candidate = project.path().join(&name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn millis(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

/// "2026-10-29T10:27:28.411Z" → ms since 1970 (UTC, no leap seconds).
fn parse_time(text: &str) -> u64 {
    let b = text.as_bytes();
    if b.len() < 19 {
        return 0;
    }
    let num = |from: usize, len: usize| text.get(from..from + len).and_then(|s| s.parse::<i64>().ok());
    let (Some(y), Some(mo), Some(d), Some(h), Some(mi), Some(s)) =
        (num(0, 4), num(5, 2), num(8, 2), num(11, 2), num(14, 2), num(17, 2))
    else {
        return 0;
    };
    let ms = text.get(20..23).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
    // Days since 1970 (Howard Hinnant's civil-from-days, inverted).
    let y = if mo <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if mo > 2 { mo - 3 } else { mo + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    let total = ((days * 24 + h) * 60 + mi) * 60 + s;
    (total.max(0) as u64) * 1000 + ms as u64
}

fn clip(text: &str, max: usize) -> String {
    let text = text.trim();
    if text.chars().count() <= max {
        return text.to_string();
    }
    let mut out: String = text.chars().take(max).collect();
    out.push('…');
    out
}

/// What Claude Code and the editor add to a user turn on their own: commands, their
/// output, reminders, the file open in the editor, the browser tools' notes.
fn is_machine_text(text: &str) -> bool {
    const MACHINE: [&str; 9] = [
        "<command-", "<local-command", "<system-reminder", "<user-prompt-submit-hook", "<ide_",
        "<browser_instruction", "<pasted_content-ignored", "Caveat:", "[Request interrupted",
    ];
    text.is_empty() || MACHINE.iter().any(|m| text.starts_with(m))
}

/// The text a user turn carries, block by block: what the editor or Claude Code
/// added is left out and what you typed stays. None when nothing of yours is left.
fn user_text(content: &Value) -> Option<String> {
    let blocks: Vec<&str> = match content {
        Value::String(s) => vec![s.as_str()],
        Value::Array(blocks) => blocks
            .iter()
            .filter(|b| b.get("type").and_then(Value::as_str) == Some("text"))
            .filter_map(|b| b.get("text").and_then(Value::as_str))
            .collect(),
        _ => return None,
    };
    let text = blocks.iter().map(|b| b.trim()).filter(|b| !is_machine_text(b)).collect::<Vec<_>>().join("\n");
    if text.is_empty() { None } else { Some(text) }
}

/// A tool Claude used, in one short line.
pub(crate) fn step_text(name: &str, input: &Value) -> String {
    let field = |k: &str| input.get(k).and_then(Value::as_str).unwrap_or("");
    let detail = match name {
        "Bash" => clip(field("command"), 160),
        "Read" | "Edit" | "MultiEdit" | "Write" | "NotebookEdit" => {
            let path = field("file_path");
            Path::new(path).file_name().and_then(|n| n.to_str()).unwrap_or(path).to_string()
        }
        "Grep" | "Glob" => clip(field("pattern"), 120),
        "WebFetch" | "WebSearch" => clip(&format!("{}{}", field("url"), field("query")), 120),
        "Task" | "Agent" => clip(field("description"), 120),
        _ => String::new(),
    };
    if detail.is_empty() { name.to_string() } else { format!("{name} · {detail}") }
}

/// The entries of one JSONL line (none for the lines that are not conversation).
fn entries_of_line(line: &str) -> Vec<Entry> {
    let Ok(v) = serde_json::from_str::<Value>(line) else { return Vec::new() };
    // Work of Claude's helper agents and meta lines are not part of the chat.
    if v.get("isSidechain").and_then(Value::as_bool) == Some(true)
        || v.get("isMeta").and_then(Value::as_bool) == Some(true)
    {
        return Vec::new();
    }
    let at = v.get("timestamp").and_then(Value::as_str).map(parse_time).unwrap_or(0);
    let Some(message) = v.get("message") else { return Vec::new() };
    let content = message.get("content").unwrap_or(&Value::Null);
    match v.get("type").and_then(Value::as_str) {
        Some("user") => user_text(content)
            .map(|text| vec![Entry { kind: "user", text: clip(&text, MAX_TEXT), at }])
            .unwrap_or_default(),
        Some("assistant") => {
            let Some(blocks) = content.as_array() else { return Vec::new() };
            let mut out = Vec::new();
            for block in blocks {
                match block.get("type").and_then(Value::as_str) {
                    Some("text") => {
                        let text = block.get("text").and_then(Value::as_str).unwrap_or("").trim();
                        if !text.is_empty() {
                            out.push(Entry { kind: "assistant", text: clip(text, MAX_TEXT), at });
                        }
                    }
                    Some("tool_use") => {
                        let name = block.get("name").and_then(Value::as_str).unwrap_or("tool");
                        let input = block.get("input").unwrap_or(&Value::Null);
                        out.push(Entry { kind: "step", text: step_text(name, input), at });
                    }
                    _ => {}
                }
            }
            out
        }
        _ => Vec::new(),
    }
}

/// The last `limit` entries of a conversation file.
fn read_tail(path: &Path, limit: usize) -> Result<Vec<Entry>, String> {
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let len = file.metadata().map_err(|e| e.to_string())?.len();
    let start = len.saturating_sub(TAIL_BYTES);
    file.seek(SeekFrom::Start(start)).map_err(|e| e.to_string())?;
    let mut bytes = Vec::with_capacity((len - start) as usize);
    file.read_to_end(&mut bytes).map_err(|e| e.to_string())?;
    let text = String::from_utf8_lossy(&bytes);
    // Cut in the middle of a line: the first one is whole only when nothing was skipped.
    let body = if start > 0 { text.split_once('\n').map(|(_, rest)| rest).unwrap_or("") } else { &text };
    let mut entries: Vec<Entry> = body.lines().flat_map(entries_of_line).collect();
    if entries.len() > limit {
        entries.drain(..entries.len() - limit);
    }
    Ok(entries)
}

/// First question and folder of a conversation, from its first bytes.
fn read_head(path: &Path) -> (String, String) {
    let Ok(mut file) = std::fs::File::open(path) else { return (String::new(), String::new()) };
    let mut buf = vec![0u8; HEAD_BYTES];
    let n = file.read(&mut buf).unwrap_or(0);
    buf.truncate(n);
    let text = String::from_utf8_lossy(&buf);
    let (mut cwd, mut title) = (String::new(), String::new());
    for line in text.lines() {
        let Ok(v) = serde_json::from_str::<Value>(line) else { continue };
        if cwd.is_empty() {
            if let Some(c) = v.get("cwd").and_then(Value::as_str) {
                cwd = c.to_string();
            }
        }
        if title.is_empty() && v.get("type").and_then(Value::as_str) == Some("user") {
            if let Some(t) = v.get("message").and_then(|m| m.get("content")).and_then(user_text) {
                title = clip(&t, 90);
            }
        }
        if !cwd.is_empty() && !title.is_empty() {
            break;
        }
    }
    (cwd, title)
}

pub(crate) fn list_sessions() -> Vec<SessionInfo> {
    let now = SystemTime::now();
    let mut found: Vec<(SystemTime, PathBuf)> = Vec::new();
    let Ok(projects) = std::fs::read_dir(projects_dir()) else { return Vec::new() };
    for project in projects.flatten() {
        let Ok(files) = std::fs::read_dir(project.path()) else { continue };
        for file in files.flatten() {
            let path = file.path();
            if path.extension().and_then(|e| e.to_str()) != Some("jsonl") {
                continue;
            }
            let Ok(modified) = file.metadata().and_then(|m| m.modified()) else { continue };
            if now.duration_since(modified).is_ok_and(|age| age > RECENT) {
                continue;
            }
            found.push((modified, path));
        }
    }
    found.sort_by(|a, b| b.0.cmp(&a.0));
    found.truncate(MAX_SESSIONS);
    found
        .into_iter()
        .filter_map(|(modified, path)| {
            let id = path.file_stem()?.to_str()?.to_string();
            if !valid_id(&id) {
                return None;
            }
            let (cwd, title) = read_head(&path);
            Some(SessionInfo { id, cwd, title, updated_at: millis(modified) })
        })
        .collect()
}

/// Claude's last answer in a conversation and when it was given, for the indicator in
/// the top bar (status.rs).
pub(crate) fn last_answer(id: &str) -> Option<(String, u64)> {
    let path = session_file(id)?;
    let entries = read_tail(&path, 60).ok()?;
    entries.into_iter().rev().find(|e| e.kind == "assistant").map(|e| (e.text, e.at))
}

/// The recent conversations, newest first.
#[tauri::command]
pub async fn returns_sessions() -> Vec<SessionInfo> {
    tauri::async_runtime::spawn_blocking(list_sessions).await.unwrap_or_default()
}

/// The end of one conversation: what you asked, what Claude answered, the tools it used.
#[tauri::command]
pub async fn returns_read(id: String, limit: Option<usize>) -> Result<Vec<Entry>, String> {
    let limit = limit.unwrap_or(80).clamp(1, 400);
    tauri::async_runtime::spawn_blocking(move || {
        let path = session_file(&id).ok_or_else(|| "unknown session".to_string())?;
        read_tail(&path, limit)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_is_named_by_an_id_never_by_a_path() {
        assert!(valid_id("3f525db3-330d-4903-a989-6e7509f8524a"));
        for bad in ["", "../x", "a/b", "a.b", "a b", "a\\b", &"x".repeat(81)] {
            assert!(!valid_id(bad), "{bad}");
            assert!(session_file(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn times_are_read_as_utc_milliseconds() {
        assert_eq!(parse_time("1970-01-01T00:00:00.000Z"), 0);
        assert_eq!(parse_time("2026-10-29T10:27:28.411Z"), 1_793_269_648_411);
        assert_eq!(parse_time("2000-02-29T12:00:00Z"), 951_825_600_000);
        assert_eq!(parse_time("nope"), 0);
    }

    #[test]
    fn what_you_asked_and_what_claude_answered_are_kept() {
        let ask = r#"{"type":"user","timestamp":"2026-10-29T10:00:00.000Z","message":{"role":"user","content":"corrige o bug"}}"#;
        let answer = r#"{"type":"assistant","timestamp":"2026-10-29T10:00:05.000Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"Pronto, corrigi."},{"type":"tool_use","name":"Edit","input":{"file_path":"/p/src/main.rs"}}]}}"#;
        let user = entries_of_line(ask);
        assert_eq!(user.len(), 1);
        assert_eq!((user[0].kind, user[0].text.as_str()), ("user", "corrige o bug"));
        let reply = entries_of_line(answer);
        assert_eq!(reply.iter().map(|e| (e.kind, e.text.as_str())).collect::<Vec<_>>(), [("assistant", "Pronto, corrigi."), ("step", "Edit · main.rs")]);
        assert!(reply[0].at > user[0].at);
    }

    #[test]
    fn tool_results_helpers_and_machine_text_are_not_chat() {
        let lines = [
            r#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"huge output"}]}}"#,
            r#"{"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}"#,
            r#"{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
            r#"{"type":"user","message":{"role":"user","content":"<system-reminder>x</system-reminder>"}}"#,
            r#"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"helper"}]}}"#,
            r#"{"type":"queue-operation","operation":"enqueue"}"#,
            "not json at all",
        ];
        for line in lines {
            assert!(entries_of_line(line).is_empty(), "{line}");
        }
    }

    #[test]
    fn a_user_turn_in_blocks_joins_its_text_and_skips_images() {
        let line = r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"olha"},{"type":"image","source":{}},{"type":"text","text":"isso"}]}}"#;
        assert_eq!(entries_of_line(line)[0].text, "olha\nisso");
    }

    #[test]
    fn what_the_editor_adds_is_dropped_but_what_you_typed_stays() {
        let line = r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>The user opened a.rs</ide_opened_file>"},{"type":"text","text":"explica isso"}]}}"#;
        let got = entries_of_line(line);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].text, "explica isso");
        let only_context = r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<browser_instruction>x</browser_instruction>"}]}}"#;
        assert!(entries_of_line(only_context).is_empty());
    }

    #[test]
    fn the_last_answer_is_the_last_thing_claude_said() {
        let dir = std::env::temp_dir().join(format!("coucou-last-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("s.jsonl");
        std::fs::write(&file, concat!(
            r#"{"type":"user","message":{"role":"user","content":"oi"}}"#, "\n",
            r#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"primeira"}]}}"#, "\n",
            r#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#, "\n",
            r#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"a ultima"}]}}"#, "\n",
            r#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}"#, "\n",
        )).unwrap();
        let entries = read_tail(&file, 60).unwrap();
        let last = entries.into_iter().rev().find(|e| e.kind == "assistant").unwrap();
        assert_eq!(last.text, "a ultima");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn steps_name_the_tool_and_what_it_touched() {
        let input = |s: &str| serde_json::from_str::<Value>(s).unwrap();
        assert_eq!(step_text("Bash", &input(r#"{"command":"cargo test"}"#)), "Bash · cargo test");
        assert_eq!(step_text("Read", &input(r#"{"file_path":"/a/b/c.ts"}"#)), "Read · c.ts");
        assert_eq!(step_text("Grep", &input(r#"{"pattern":"fn main"}"#)), "Grep · fn main");
        assert_eq!(step_text("TodoWrite", &input("{}")), "TodoWrite");
    }

    #[test]
    fn only_the_end_of_a_long_file_is_read_and_a_cut_line_is_dropped() {
        let dir = std::env::temp_dir().join(format!("coucou-returns-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("s.jsonl");
        let mut body = String::new();
        for i in 0..6000 {
            body.push_str(&format!(
                "{{\"type\":\"user\",\"message\":{{\"role\":\"user\",\"content\":\"pergunta numero {i} {}\"}}}}\n",
                "x".repeat(200)
            ));
        }
        std::fs::write(&file, &body).unwrap();
        assert!(body.len() as u64 > TAIL_BYTES);
        let got = read_tail(&file, 5).unwrap();
        assert_eq!(got.len(), 5);
        assert!(got[4].text.starts_with("pergunta numero 5999"));
        assert!(got[0].text.starts_with("pergunta numero 5995"));
        let (_, title) = read_head(&file);
        assert!(title.starts_with("pergunta numero 0"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Against the conversations on this computer: `cargo test -- --ignored real_sessions --nocapture`.
    #[test]
    #[ignore]
    fn real_sessions() {
        let sessions = list_sessions();
        println!("{} sessions", sessions.len());
        for s in sessions.iter().take(3) {
            println!("- {} | {} | {} | {}", s.id, s.cwd, s.updated_at, s.title);
        }
        if let Some(first) = sessions.first() {
            let entries = read_tail(&session_file(&first.id).unwrap(), 6).unwrap();
            for e in entries {
                println!("  [{}] {}", e.kind, e.text.chars().take(100).collect::<String>().replace('\n', " "));
            }
        }
    }
}
