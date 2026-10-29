// What the agents are doing right now, written to a small file for the
// indicator in the desktop's top bar (windows/wingpanel-indicator): the
// indicator is a separate program inside the panel, so it reads this file
// instead of talking to Coucou.
//
//   ~/.local/share/coucou/status.json
//
// It holds the state of every recent session (working, waiting for you,
// finished…), the one state the bar's icon shows, and the last answer Claude
// gave. Never a prompt, a command's output or a file's contents: the same
// short step lines the island shows, and Claude's last answer, cut short.
// Nothing here reaches the network; the file is private to the user (0600).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::Value;

/// How many recent steps a session keeps.
const MAX_STEPS: usize = 3;
/// A session nobody touched for this long is dropped from the file.
const FORGET_AFTER_MS: u64 = 30 * 60 * 1000;
/// "Finished" is shown this long, then the icon rests.
const FINISHED_FOR_MS: u64 = 3 * 60 * 1000;
/// The last answer is cut to this many characters.
const MAX_ANSWER: usize = 700;
/// Events come in bursts (a tool each fraction of a second): the file is
/// rewritten at most this often unless the state changes.
const MIN_GAP: Duration = Duration::from_millis(400);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Idle,
    Finished,
    Working,
    Error,
    Waiting,
}

impl State {
    /// What the bar's icon shows when several sessions disagree: the one that
    /// needs you most.
    fn rank(self) -> u8 {
        match self {
            State::Idle => 0,
            State::Finished => 1,
            State::Working => 2,
            State::Error => 3,
            State::Waiting => 4,
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SessionStatus {
    pub id: String,
    pub project: String,
    pub state: State,
    /// The tool in use, as the island writes it ("Edit · main.rs").
    pub detail: String,
    /// The last few tools, oldest first, ending with `detail`.
    pub steps: Vec<String>,
    pub updated_at: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LastAnswer {
    pub project: String,
    pub text: String,
    pub at: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub version: u32,
    /// The process that wrote it: the indicator shows "off" when it is gone.
    pub pid: u32,
    /// How to bring Coucou up (`<exe> --shortcut openChat`).
    pub exe: String,
    pub state: State,
    pub updated_at: u64,
    pub sessions: Vec<SessionStatus>,
    pub last_answer: Option<LastAnswer>,
}

#[derive(Default)]
struct Tracker {
    sessions: HashMap<String, SessionStatus>,
    last_answer: Option<LastAnswer>,
}

fn basename(path: &str) -> String {
    path.split(['/', '\\']).filter(|p| !p.is_empty()).next_back().unwrap_or("").to_string()
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

impl Tracker {
    /// Applies one hook event. Returns whether anything the file shows changed.
    fn apply(&mut self, event: &str, payload: &Value, now: u64) -> bool {
        let id = payload.get("session_id").and_then(Value::as_str).unwrap_or("");
        if id.is_empty() || id.len() > 100 {
            return false;
        }
        if event == "SessionEnd" {
            return self.sessions.remove(id).is_some();
        }
        let (state, detail) = match event {
            "SessionStart" => (State::Idle, String::new()),
            "UserPromptSubmit" => (State::Working, String::new()),
            "PreToolUse" => (State::Working, tool_line(payload)),
            "PostToolUse" | "PostToolUseFailure" | "SubagentStart" | "SubagentStop" => (State::Working, String::new()),
            "PermissionRequest" => (State::Waiting, tool_line(payload)),
            "Stop" => (State::Finished, String::new()),
            "StopFailure" => (State::Error, String::new()),
            _ => return false,
        };
        let project = payload.get("cwd").and_then(Value::as_str).map(basename).unwrap_or_default();
        let entry = self.sessions.entry(id.to_string()).or_insert_with(|| SessionStatus {
            id: id.to_string(),
            project: project.clone(),
            state: State::Idle,
            detail: String::new(),
            steps: Vec::new(),
            updated_at: now,
        });
        // A tool finishing keeps the line of the tool that ran; only a new one replaces it.
        let keep_detail = detail.is_empty() && state == State::Working && entry.state == State::Working;
        let changed = entry.state != state || (!keep_detail && entry.detail != detail);
        entry.state = state;
        if event == "UserPromptSubmit" {
            // A new question starts a new list of steps.
            entry.steps.clear();
        }
        if !keep_detail {
            if !detail.is_empty() && entry.steps.last() != Some(&detail) {
                entry.steps.push(detail.clone());
                if entry.steps.len() > MAX_STEPS {
                    entry.steps.remove(0);
                }
            }
            entry.detail = detail;
        }
        if !project.is_empty() {
            entry.project = project;
        }
        entry.updated_at = now;
        changed
    }

    fn set_answer(&mut self, project: &str, text: &str, at: u64) {
        let text = clip(text, MAX_ANSWER);
        if !text.is_empty() {
            self.last_answer = Some(LastAnswer { project: project.to_string(), text, at });
        }
    }

    fn snapshot(&mut self, now: u64) -> Snapshot {
        self.sessions.retain(|_, s| now.saturating_sub(s.updated_at) < FORGET_AFTER_MS);
        let mut sessions: Vec<SessionStatus> = self.sessions.values().cloned().collect();
        // A finished session rests after a while.
        for s in &mut sessions {
            if s.state == State::Finished && now.saturating_sub(s.updated_at) > FINISHED_FOR_MS {
                s.state = State::Idle;
            }
        }
        sessions.sort_by(|a, b| b.state.rank().cmp(&a.state.rank()).then(b.updated_at.cmp(&a.updated_at)));
        sessions.truncate(8);
        let state = sessions.iter().map(|s| s.state).max_by_key(|s| s.rank()).unwrap_or(State::Idle);
        Snapshot {
            version: 1,
            pid: std::process::id(),
            exe: std::env::current_exe().map(|p| p.to_string_lossy().to_string()).unwrap_or_default(),
            state,
            updated_at: now,
            sessions,
            last_answer: self.last_answer.clone(),
        }
    }
}

/// "Edit · main.rs": the tool of a hook payload, in one short line.
fn tool_line(payload: &Value) -> String {
    let name = payload.get("tool_name").and_then(Value::as_str).unwrap_or("");
    if name.is_empty() {
        return String::new();
    }
    let line = crate::returns::step_text(name, payload.get("tool_input").unwrap_or(&Value::Null));
    // One short line: a command of several lines would break the indicator's layout.
    let one: String = line.split_whitespace().collect::<Vec<_>>().join(" ");
    clip(&one, 64)
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn file() -> PathBuf {
    crate::platform::local_dir().join("status.json")
}

static TRACKER: Mutex<Option<Tracker>> = Mutex::new(None);
static LAST_WRITE: Mutex<Option<Instant>> = Mutex::new(None);

fn write(snapshot: &Snapshot) {
    let path = file();
    let Some(dir) = path.parent() else { return };
    if std::fs::create_dir_all(dir).is_err() {
        return;
    }
    let Ok(bytes) = serde_json::to_vec(snapshot) else { return };
    let tmp = dir.join(".status.json.tmp");
    if std::fs::write(&tmp, bytes).is_err() {
        return;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600));
    }
    let _ = std::fs::rename(&tmp, &path);
}

fn flush(force: bool) {
    {
        let mut last = LAST_WRITE.lock().unwrap();
        if !force && last.is_some_and(|t| t.elapsed() < MIN_GAP) {
            return;
        }
        *last = Some(Instant::now());
    }
    let snapshot = TRACKER.lock().unwrap().get_or_insert_with(Tracker::default).snapshot(now_ms());
    write(&snapshot);
}

/// At launch: the file says "idle" and names this process, so what a previous run left is gone.
pub fn reset() {
    *TRACKER.lock().unwrap() = Some(Tracker::default());
    flush(true);
}

/// A hook event came in. Called for every one; most change nothing.
pub fn observe(payload: &Value, event: &str) {
    let changed = {
        let mut guard = TRACKER.lock().unwrap();
        guard.get_or_insert_with(Tracker::default).apply(event, payload, now_ms())
    };
    if changed || event == "Stop" {
        flush(event == "Stop" || event == "PermissionRequest" || event == "StopFailure" || event == "SessionEnd");
    }
    if event == "Stop" {
        let id = payload.get("session_id").and_then(Value::as_str).unwrap_or("").to_string();
        let project = payload.get("cwd").and_then(Value::as_str).map(basename).unwrap_or_default();
        // Claude Code may fire Stop a moment before the answer is on disk.
        std::thread::spawn(move || {
            for wait in [450u64, 1500] {
                std::thread::sleep(Duration::from_millis(wait));
                if let Some((text, at)) = crate::returns::last_answer(&id) {
                    TRACKER.lock().unwrap().get_or_insert_with(Tracker::default).set_answer(&project, &text, at);
                    flush(true);
                    break;
                }
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn ev(t: &mut Tracker, event: &str, session: &str, now: u64) -> bool {
        t.apply(event, &json!({ "session_id": session, "cwd": "/home/me/projeto" }), now)
    }

    #[test]
    fn a_prompt_starts_work_and_stop_finishes_it() {
        let mut t = Tracker::default();
        assert!(ev(&mut t, "UserPromptSubmit", "a", 1000));
        let s = t.snapshot(1000);
        assert_eq!((s.state, s.sessions[0].project.as_str()), (State::Working, "projeto"));
        assert!(ev(&mut t, "Stop", "a", 2000));
        assert_eq!(t.snapshot(2000).state, State::Finished);
    }

    #[test]
    fn finished_rests_after_a_while() {
        let mut t = Tracker::default();
        ev(&mut t, "Stop", "a", 1000);
        assert_eq!(t.snapshot(1000 + FINISHED_FOR_MS - 1).state, State::Finished);
        assert_eq!(t.snapshot(1000 + FINISHED_FOR_MS + 1).state, State::Idle);
    }

    #[test]
    fn the_session_that_needs_you_wins_the_icon() {
        let mut t = Tracker::default();
        ev(&mut t, "UserPromptSubmit", "a", 1000);
        t.apply("PermissionRequest", &json!({ "session_id": "b", "cwd": "/x/y", "tool_name": "Bash", "tool_input": { "command": "rm -r build" } }), 1100);
        let s = t.snapshot(1200);
        assert_eq!(s.state, State::Waiting);
        assert_eq!(s.sessions[0].id, "b");
        assert_eq!(s.sessions[0].detail, "Bash · rm -r build");
        // Answered: the next tool brings it back to work.
        t.apply("PostToolUse", &json!({ "session_id": "b", "cwd": "/x/y" }), 1300);
        assert_eq!(t.snapshot(1300).state, State::Working);
    }

    #[test]
    fn a_tool_line_stays_until_another_tool_replaces_it() {
        let mut t = Tracker::default();
        t.apply("PreToolUse", &json!({ "session_id": "a", "tool_name": "Read", "tool_input": { "file_path": "/p/a.rs" } }), 1);
        t.apply("PostToolUse", &json!({ "session_id": "a" }), 2);
        assert_eq!(t.snapshot(3).sessions[0].detail, "Read · a.rs");
        t.apply("PreToolUse", &json!({ "session_id": "a", "tool_name": "Bash", "tool_input": { "command": "ls" } }), 4);
        assert_eq!(t.snapshot(5).sessions[0].detail, "Bash · ls");
    }

    #[test]
    fn the_last_steps_are_kept_and_a_new_question_clears_them() {
        let mut t = Tracker::default();
        for (i, cmd) in ["a", "b", "c", "d"].iter().enumerate() {
            t.apply("PreToolUse", &json!({ "session_id": "s", "tool_name": "Bash", "tool_input": { "command": cmd } }), i as u64 + 1);
        }
        assert_eq!(t.snapshot(9).sessions[0].steps, ["Bash · b", "Bash · c", "Bash · d"]);
        // The same tool twice in a row is one line.
        t.apply("PreToolUse", &json!({ "session_id": "s", "tool_name": "Bash", "tool_input": { "command": "d" } }), 10);
        assert_eq!(t.snapshot(11).sessions[0].steps.len(), 3);
        t.apply("UserPromptSubmit", &json!({ "session_id": "s" }), 12);
        assert!(t.snapshot(13).sessions[0].steps.is_empty());
    }

    #[test]
    fn a_step_is_one_short_line_even_for_a_long_multiline_command() {
        let long = format!("cd /a/b &&\n  cat > x <<'EOF'\n{}\nEOF", "y".repeat(300));
        let line = tool_line(&json!({ "tool_name": "Bash", "tool_input": { "command": long } }));
        assert!(!line.contains('\n'));
        assert!(line.chars().count() <= 65, "{line}");
        assert!(line.starts_with("Bash · cd /a/b && cat"));
    }

    #[test]
    fn a_failed_turn_shows_an_error_and_a_session_end_removes_the_session() {
        let mut t = Tracker::default();
        ev(&mut t, "StopFailure", "a", 1);
        assert_eq!(t.snapshot(2).state, State::Error);
        assert!(ev(&mut t, "SessionEnd", "a", 3));
        assert_eq!(t.snapshot(4).state, State::Idle);
        assert!(t.snapshot(4).sessions.is_empty());
        // Ending a session nobody knows is not news.
        assert!(!ev(&mut t, "SessionEnd", "zzz", 5));
    }

    #[test]
    fn old_sessions_are_forgotten_and_unknown_events_do_nothing() {
        let mut t = Tracker::default();
        ev(&mut t, "UserPromptSubmit", "a", 1);
        assert!(!ev(&mut t, "StatusLine", "a", 2));
        assert!(!ev(&mut t, "Notification", "a", 2));
        assert!(t.snapshot(1 + FORGET_AFTER_MS + 1).sessions.is_empty());
        // No session id: nothing to follow.
        assert!(!t.apply("Stop", &json!({}), 3));
    }

    #[test]
    fn the_last_answer_is_cut_short() {
        let mut t = Tracker::default();
        t.set_answer("p", &"x".repeat(2000), 5);
        let a = t.snapshot(6).last_answer.unwrap();
        assert_eq!(a.text.chars().count(), MAX_ANSWER + 1);
        t.set_answer("p", "   ", 7);
        assert_eq!(t.snapshot(8).last_answer.unwrap().at, 5, "an empty answer changes nothing");
    }

    #[test]
    fn the_file_holds_the_keys_the_indicator_reads() {
        let mut t = Tracker::default();
        ev(&mut t, "UserPromptSubmit", "a", 1);
        let v = serde_json::to_value(t.snapshot(2)).unwrap();
        for key in ["version", "pid", "exe", "state", "updatedAt", "sessions", "lastAnswer"] {
            assert!(v.get(key).is_some(), "{key}");
        }
        assert_eq!(v["state"], "working");
        assert_eq!(v["sessions"][0]["updatedAt"], 1);
    }
}
