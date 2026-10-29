// What the agents are doing right now, written to a small file for the
// indicator in the desktop's top bar (windows/wingpanel-indicator): the
// indicator is a separate program inside the panel, so it reads this file
// instead of talking to SlimIA.
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
/// An idle or finished session leaves the list after this long: it is not doing anything.
const INACTIVE_FOR_MS: u64 = 2 * 60 * 1000;
/// "Finished" is shown this long, then the icon rests.
const FINISHED_FOR_MS: u64 = INACTIVE_FOR_MS;
/// The last answer is cut to this many characters.
const MAX_ANSWER: usize = 8000;
/// Events come in bursts (a tool each fraction of a second): the file is
/// rewritten at most this often unless the state changes.
const MIN_GAP: Duration = Duration::from_millis(400);

/// The states of Mochi on the island (BOT_STATES in src/mochi/engine.ts) that a hook can cause.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Idle,
    Finished,
    Thinking,
    Working,
    Ratelimit,
    Error,
    /// Claude Code asks you a question (AskUserQuestion).
    Question,
    /// A permission waits for your Allow or Deny.
    Approval,
}

impl State {
    /// What the bar's icon shows when several sessions disagree: the one that
    /// needs you most.
    fn rank(self) -> u8 {
        match self {
            State::Idle => 0,
            State::Finished => 1,
            State::Thinking => 2,
            State::Working => 3,
            State::Ratelimit => 4,
            State::Error => 5,
            State::Question => 6,
            State::Approval => 7,
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SessionStatus {
    pub id: String,
    pub project: String,
    /// Which agent: "claude", "codex", "gemini"… (the pill it has on the island).
    pub agent: String,
    /// That pill's colour, "#RRGGBB".
    pub color: String,
    pub state: State,
    /// The tool in use, as the island writes it ("Edit · main.rs").
    pub detail: String,
    /// The last few tools, oldest first, ending with `detail`.
    pub steps: Vec<String>,
    /// The permission request waiting for an answer, when the state is `approval`.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub request: String,
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
    /// How to bring SlimIA up (`<exe> --shortcut openChat`).
    pub exe: String,
    pub state: State,
    pub updated_at: u64,
    pub sessions: Vec<SessionStatus>,
    pub last_answer: Option<LastAnswer>,
    /// The Spotify player as the island's pill sees it (cover left out), or none.
    pub music: Option<Value>,
}

#[derive(Default)]
struct Tracker {
    sessions: HashMap<String, SessionStatus>,
    last_answer: Option<LastAnswer>,
    music: Option<Value>,
}

/// The agent a hook comes from, as the island routes it: a tagged agent, Cursor's
/// terminal, else Claude Code.
fn agent_of(payload: &Value) -> String {
    let tag = payload.get("coucou_agent").and_then(Value::as_str).unwrap_or("");
    let valid = !tag.is_empty()
        && tag.len() <= 24
        && tag != "claude"
        && tag.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_');
    if valid {
        return tag.to_string();
    }
    if payload.get("term_editor").and_then(Value::as_str) == Some("cursor") {
        return "cursor".to_string();
    }
    "claude".to_string()
}

/// The pill colours of the catalog (src/core/pills.ts, island/agents.ts).
fn agent_color(agent: &str) -> &'static str {
    match agent {
        "claude" => "#F5F6F8",
        "cursor" => "#C0C4CC",
        "antigravity" => "#E879F9",
        "codex" => "#2DD4BF",
        "gemini" => "#8AB4F8",
        "copilot" => "#818CF8",
        "muse" => "#38BDF8",
        "opencode" => "#4ADE80",
        "amp" => "#F59E0B",
        "hermes" => "#C084FC",
        _ => "#9AA0AA",
    }
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
        let tool = payload.get("tool_name").and_then(Value::as_str).unwrap_or("");
        let message = payload.get("message").and_then(Value::as_str).unwrap_or("").to_lowercase();
        let (state, detail) = match event {
            "SessionStart" | "Interrupt" => (State::Idle, String::new()),
            "UserPromptSubmit" => (State::Thinking, String::new()),
            "PreToolUse" if tool == "ask_question" || tool.ends_with(":ask_question") => (State::Question, tool_line(payload)),
            "PreToolUse" => (State::Working, tool_line(payload)),
            "PostToolUse" | "PostToolUseFailure" | "SubagentStart" | "SubagentStop" => (State::Working, String::new()),
            "Notification" if message.contains("rate limit") || message.contains("limite d") => (State::Ratelimit, String::new()),
            "Notification" if message.ends_with('?') => (State::Question, String::new()),
            "PermissionRequest" if tool == "AskUserQuestion" => (State::Question, String::new()),
            "PermissionRequest" => (State::Approval, tool_line(payload)),
            "Stop" => (State::Finished, String::new()),
            "StopFailure" => (State::Error, String::new()),
            _ => return false,
        };
        let project = payload.get("cwd").and_then(Value::as_str).map(basename).unwrap_or_default();
        let agent = agent_of(payload);
        let entry = self.sessions.entry(id.to_string()).or_insert_with(|| SessionStatus {
            id: id.to_string(),
            project: project.clone(),
            agent: agent.clone(),
            color: agent_color(&agent).to_string(),
            state: State::Idle,
            detail: String::new(),
            steps: Vec::new(),
            request: String::new(),
            updated_at: now,
        });
        // A tool finishing keeps the line of the tool that ran; only a new one replaces it.
        let keep_detail = detail.is_empty() && matches!(state, State::Working | State::Thinking) && matches!(entry.state, State::Working | State::Thinking);
        let changed = entry.state != state || (!keep_detail && entry.detail != detail);
        entry.state = state;
        entry.request = match state {
            State::Approval => payload.get("request_id").and_then(Value::as_str).unwrap_or("").to_string(),
            _ => String::new(),
        };
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

    fn set_music(&mut self, music: Option<Value>) -> bool {
        let changed = self.music != music;
        self.music = music;
        changed
    }

    fn set_answer(&mut self, project: &str, text: &str, at: u64) {
        let text = clip(text, MAX_ANSWER);
        if !text.is_empty() {
            self.last_answer = Some(LastAnswer { project: project.to_string(), text, at });
        }
    }

    fn snapshot(&mut self, now: u64) -> Snapshot {
        // Claude Code always keeps one pill online: the one that spoke last stays, idle or not,
        // until its session ends. The other agents leave when they have nothing going on.
        let keep = self.sessions.values().filter(|s| s.agent == "claude").max_by_key(|s| s.updated_at).map(|s| s.id.clone());
        self.sessions.retain(|id, s| {
            if keep.as_deref() == Some(id.as_str()) {
                return true;
            }
            let limit = if matches!(s.state, State::Idle | State::Finished | State::Error) { INACTIVE_FOR_MS } else { FORGET_AFTER_MS };
            now.saturating_sub(s.updated_at) < limit
        });
        let mut sessions: Vec<SessionStatus> = self.sessions.values().cloned().collect();
        // A finished or failed session rests after a while.
        for s in &mut sessions {
            if matches!(s.state, State::Finished | State::Error) && now.saturating_sub(s.updated_at) > FINISHED_FOR_MS {
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
            music: self.music.clone(),
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

/// The Spotify player changed (src-tauri/src/spotify.rs): the indicator shows the
/// track and dances to it. The cover is left out, and nothing is kept when Spotify is not running.
pub fn music(state: &impl Serialize) {
    let mut value = serde_json::to_value(state).ok();
    if let Some(Value::Object(map)) = value.as_mut() {
        if let Some(Value::Object(track)) = map.get_mut("track") {
            track.remove("artUrl");
        }
        if map.get("running") == Some(&Value::Bool(false)) {
            value = None;
        }
    }
    let changed = TRACKER.lock().unwrap().get_or_insert_with(Tracker::default).set_music(value);
    if changed {
        flush(false);
    }
}

/// A permission request was answered (from the island or the bar): its buttons go away.
/// Answered: Claude goes on working. Not answered (timed out, or handed to the terminal):
/// the buttons go but the alert stays until the next event, because it still waits for you.
pub fn resolve(request_id: &str, answered: bool) {
    let changed = {
        let mut guard = TRACKER.lock().unwrap();
        let t = guard.get_or_insert_with(Tracker::default);
        let mut any = false;
        for s in t.sessions.values_mut().filter(|s| !request_id.is_empty() && s.request == request_id) {
            s.request.clear();
            if answered {
                s.state = State::Working;
            }
            any = true;
        }
        any
    };
    if changed {
        flush(true);
    }
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
        assert_eq!((s.state, s.sessions[0].project.as_str()), (State::Thinking, "projeto"));
        assert!(ev(&mut t, "PreToolUse", "a", 1500));
        assert_eq!(t.snapshot(1500).state, State::Working);
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
        assert_eq!(s.state, State::Approval);
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
    fn an_idle_or_finished_session_leaves_the_list_but_a_busy_one_stays() {
        let mut t = Tracker::default();
        ev(&mut t, "SessionStart", "idle", 1);
        ev(&mut t, "Stop", "done", 2);
        ev(&mut t, "UserPromptSubmit", "busy", 3);
        let ids = |t: &mut Tracker, now| {
            let mut v: Vec<String> = t.snapshot(now).sessions.into_iter().map(|s| s.id).collect();
            v.sort();
            v
        };
        assert_eq!(ids(&mut t, 1000), ["busy", "done", "idle"]);
        assert_eq!(ids(&mut t, 1 + INACTIVE_FOR_MS + 1), ["busy"]);
    }

    #[test]
    fn the_newest_claude_session_stays_online_and_the_other_agents_leave() {
        let mut t = Tracker::default();
        ev(&mut t, "SessionStart", "old", 1);
        ev(&mut t, "Stop", "claude-new", 50);
        t.apply("Stop", &json!({ "session_id": "gemini", "cwd": "/x/y", "coucou_agent": "gemini" }), 60);
        let later = 1 + FORGET_AFTER_MS + 10;
        let ids: Vec<String> = t.snapshot(later).sessions.into_iter().map(|s| s.id).collect();
        assert_eq!(ids, ["claude-new"]);
    }

    #[test]
    fn old_sessions_are_forgotten_and_unknown_events_do_nothing() {
        let mut t = Tracker::default();
        t.apply("UserPromptSubmit", &json!({ "session_id": "a", "cwd": "/x/y", "coucou_agent": "gemini" }), 1);
        assert!(!ev(&mut t, "StatusLine", "a", 2));
        assert!(!ev(&mut t, "Notification", "a", 2));
        assert!(t.snapshot(1 + FORGET_AFTER_MS + 1).sessions.is_empty());
        // No session id: nothing to follow.
        assert!(!t.apply("Stop", &json!({}), 3));
    }

    #[test]
    fn the_island_states_come_from_the_same_events() {
        let mut t = Tracker::default();
        let state = |t: &mut Tracker| t.snapshot(9).state;
        t.apply("Notification", &json!({ "session_id": "a", "message": "Rate limit reached" }), 1);
        assert_eq!(state(&mut t), State::Ratelimit);
        t.apply("Notification", &json!({ "session_id": "a", "message": "Which one do you prefer?" }), 2);
        assert_eq!(state(&mut t), State::Question);
        t.apply("PermissionRequest", &json!({ "session_id": "a", "tool_name": "AskUserQuestion" }), 3);
        assert_eq!(state(&mut t), State::Question);
        t.apply("PermissionRequest", &json!({ "session_id": "a", "tool_name": "Bash", "tool_input": { "command": "ls" } }), 4);
        assert_eq!(state(&mut t), State::Approval);
        t.apply("Interrupt", &json!({ "session_id": "a" }), 5);
        assert_eq!(state(&mut t), State::Idle);
        // A notification that says nothing we know changes nothing.
        assert!(!t.apply("Notification", &json!({ "session_id": "a", "message": "Claude is waiting for your input" }), 6));
    }

    #[test]
    fn each_session_knows_its_agent_and_the_pill_colour() {
        let mut t = Tracker::default();
        t.apply("Stop", &json!({ "session_id": "c" }), 1);
        t.apply("Stop", &json!({ "session_id": "g", "coucou_agent": "gemini" }), 2);
        t.apply("Stop", &json!({ "session_id": "x", "term_editor": "cursor" }), 3);
        t.apply("Stop", &json!({ "session_id": "bad", "coucou_agent": "Has Space" }), 4);
        let s = t.snapshot(5);
        let of = |id: &str| s.sessions.iter().find(|x| x.id == id).map(|x| (x.agent.clone(), x.color.clone())).unwrap();
        assert_eq!(of("c"), ("claude".into(), "#F5F6F8".into()));
        assert_eq!(of("g"), ("gemini".into(), "#8AB4F8".into()));
        assert_eq!(of("x"), ("cursor".into(), "#C0C4CC".into()));
        assert_eq!(of("bad").0, "claude", "an invalid tag falls back to Claude Code, like the island");
    }

    #[test]
    fn the_music_is_kept_without_its_cover_and_forgotten_when_spotify_closes() {
        let mut t = Tracker::default();
        let playing = json!({ "running": true, "playing": true, "track": { "id": "spotify:track:1", "title": "T", "artist": "A", "album": "", "duration": 200.0, "artUrl": "https://x" }, "position": 3.0, "positionAt": 1000.0 });
        let mut value = playing.clone();
        value["track"].as_object_mut().unwrap().remove("artUrl");
        assert!(t.set_music(Some(value.clone())));
        assert!(!t.set_music(Some(value)), "the same state again is no news");
        assert_eq!(t.snapshot(1).music.unwrap()["track"]["title"], "T");
        assert!(t.set_music(None));
        assert!(t.snapshot(2).music.is_none());
    }

    #[test]
    fn the_last_answer_is_cut_short() {
        let mut t = Tracker::default();
        t.set_answer("p", &"x".repeat(MAX_ANSWER + 2000), 5);
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
        for key in ["version", "pid", "exe", "state", "updatedAt", "sessions", "lastAnswer", "music"] {
            assert!(v.get(key).is_some(), "{key}");
        }
        assert_eq!(v["state"], "thinking");
        assert_eq!(v["sessions"][0]["updatedAt"], 1);
    }
}
