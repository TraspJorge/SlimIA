// Coucou in the top bar: a small Mochi that changes colour with what the agents
// are doing, and a panel with the sessions and Claude's last answer.
//
// It does not talk to Coucou: it reads ~/.local/share/coucou/status.json, which
// the Coucou app rewrites on every hook event (src-tauri/src/status.rs). It opens
// no connection and runs nothing but Coucou's own `--shortcut openChat` when you
// press "Open Coucou". If Coucou is not running the Mochi is grey.

namespace Coucou {
    public enum Mood {
        OFF, IDLE, FINISHED, WORKING, ERROR, WAITING;

        public static Mood parse (string? name) {
            switch (name) {
                case "idle": return IDLE;
                case "finished": return FINISHED;
                case "working": return WORKING;
                case "error": return ERROR;
                case "waiting": return WAITING;
                default: return IDLE;
            }
        }

        public bool pulses () {
            return this == WORKING || this == WAITING;
        }

        // Body colour of the Mochi in the bar.
        public void rgb (out double r, out double g, out double b) {
            switch (this) {
                case WORKING: r = 0.231; g = 0.620; b = 1.000; break;   // #3B9EFF
                case WAITING: r = 0.961; g = 0.647; b = 0.141; break;   // #F5A524
                case FINISHED: r = 0.204; g = 0.827; b = 0.600; break;  // #34D399
                case ERROR: r = 0.957; g = 0.314; b = 0.369; break;     // #F4505E
                case OFF: r = 0.45; g = 0.46; b = 0.50; break;
                default: r = 0.961; g = 0.965; b = 0.973; break;        // #F5F6F8
            }
        }
    }

    // Text in the user's language: Portuguese when the locale is, English otherwise.
    string tr (string en, string pt) {
        var lang = Environment.get_variable ("LANGUAGE") ?? Environment.get_variable ("LC_MESSAGES")
            ?? Environment.get_variable ("LANG") ?? "";
        return lang.has_prefix ("pt") ? pt : en;
    }

    public class SessionRow : Gtk.Box {
        public SessionRow (string project, string detail, Mood mood) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 8);
            var dot = new Gtk.DrawingArea ();
            dot.set_size_request (10, 10);
            dot.valign = Gtk.Align.CENTER;
            dot.draw.connect ((cr) => {
                double r, g, b;
                mood.rgb (out r, out g, out b);
                cr.set_source_rgb (r, g, b);
                cr.arc (5, 5, 4.5, 0, 2 * Math.PI);
                cr.fill ();
                return true;
            });
            var name = new Gtk.Label (project == "" ? "Claude Code" : project);
            name.get_style_context ().add_class ("title");
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.max_width_chars = 18;
            var text = new Gtk.Label (detail);
            text.xalign = 0;
            text.hexpand = true;
            text.ellipsize = Pango.EllipsizeMode.END;
            text.max_width_chars = 30;
            text.opacity = 0.65;
            pack_start (dot, false, false, 0);
            pack_start (name, false, false, 0);
            pack_start (text, true, true, 0);
        }
    }

    public class Indicator : Wingpanel.Indicator {
        private const int ICON_SIZE = 24;

        private Gtk.DrawingArea? mochi = null;
        private Gtk.Box? panel = null;
        private Gtk.Label? headline = null;
        private Gtk.Box? sessions_box = null;
        private Gtk.Label? answer_title = null;
        private Gtk.Label? answer_text = null;
        private Gtk.Button? open_button = null;

        private Mood mood = Mood.OFF;
        private string exe = "";
        private Json.Array? sessions = null;
        private string answer_project = "";
        private string answer_body = "";
        private int64 answer_at = 0;
        private uint64 phase = 0;
        private uint poll_id = 0;
        private uint tick_id = 0;
        private string last_raw = "";

        public Indicator () {
            Object (code_name: "coucou");
            visible = true;
        }

        private static string status_path () {
            return Path.build_filename (Environment.get_user_data_dir (), "coucou", "status.json");
        }

        public override Gtk.Widget get_display_widget () {
            if (mochi == null) {
                mochi = new Gtk.DrawingArea ();
                mochi.set_size_request (ICON_SIZE + 6, ICON_SIZE);
                mochi.draw.connect (draw_mochi);
                refresh ();
                // The file is tiny: reading it once a second costs nothing.
                poll_id = Timeout.add_seconds (1, () => { refresh (); return true; });
            }
            return mochi;
        }

        public override Gtk.Widget? get_widget () {
            if (panel == null) {
                panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
                panel.margin = 14;
                panel.set_size_request (360, -1);

                headline = new Gtk.Label ("");
                headline.xalign = 0;
                headline.get_style_context ().add_class ("h3");
                panel.pack_start (headline, false, false, 0);

                sessions_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
                panel.pack_start (sessions_box, false, false, 0);

                panel.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);

                answer_title = new Gtk.Label ("");
                answer_title.xalign = 0;
                answer_title.opacity = 0.65;
                panel.pack_start (answer_title, false, false, 0);

                answer_text = new Gtk.Label ("");
                answer_text.xalign = 0;
                answer_text.yalign = 0;
                answer_text.wrap = true;
                answer_text.wrap_mode = Pango.WrapMode.WORD_CHAR;
                answer_text.max_width_chars = 46;
                answer_text.selectable = true;
                panel.pack_start (answer_text, false, false, 0);

                open_button = new Gtk.Button.with_label (tr ("Open Coucou", "Abrir o Coucou"));
                open_button.clicked.connect (open_coucou);
                panel.pack_start (open_button, false, false, 0);

                panel.show_all ();
                update_panel ();
            }
            return panel;
        }

        public override void opened () {
            refresh ();
        }

        public override void closed () {
        }

        private void open_coucou () {
            close ();
            if (exe == "") {
                return;
            }
            try {
                // A second launch only brings the running Coucou forward (single instance).
                Process.spawn_async (null, { exe, "--shortcut", "openChat" }, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, null);
            } catch (Error e) {
                warning ("coucou: could not open: %s", e.message);
            }
        }

        // ── Reading the status file ──────────────────────────────────────────

        private void refresh () {
            string raw;
            try {
                FileUtils.get_contents (status_path (), out raw);
            } catch (Error e) {
                apply_off ();
                return;
            }
            if (raw == last_raw && mood != Mood.OFF && !is_stale ()) {
                return;
            }
            last_raw = raw;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (raw);
                var root = parser.get_root ().get_object ();
                var pid = (uint) root.get_int_member_with_default ("pid", 0);
                if (pid == 0 || !FileUtils.test ("/proc/%u".printf (pid), FileTest.EXISTS)) {
                    apply_off ();
                    return;
                }
                exe = root.get_string_member_with_default ("exe", "");
                var next = Mood.parse (root.get_string_member_with_default ("state", "idle"));
                sessions = root.has_member ("sessions") ? root.get_array_member ("sessions") : null;
                answer_project = ""; answer_body = ""; answer_at = 0;
                if (root.has_member ("lastAnswer") && !root.get_null_member ("lastAnswer")) {
                    var a = root.get_object_member ("lastAnswer");
                    answer_project = a.get_string_member_with_default ("project", "");
                    answer_body = a.get_string_member_with_default ("text", "");
                    answer_at = a.get_int_member_with_default ("at", 0);
                }
                set_mood (next);
            } catch (Error e) {
                apply_off ();
            }
        }

        private bool is_stale () {
            return false;
        }

        private void apply_off () {
            sessions = null;
            last_raw = "";
            set_mood (Mood.OFF);
        }

        private void set_mood (Mood next) {
            mood = next;
            // Working and waiting breathe; the rest holds still and costs nothing.
            if (mood.pulses () && tick_id == 0) {
                tick_id = Timeout.add (90, () => {
                    phase++;
                    if (mochi != null) mochi.queue_draw ();
                    if (!mood.pulses ()) {
                        tick_id = 0;
                        return false;
                    }
                    return true;
                });
            }
            if (mochi != null) mochi.queue_draw ();
            update_panel ();
        }

        // ── The Mochi in the bar ─────────────────────────────────────────────

        private bool draw_mochi (Cairo.Context cr) {
            int w = mochi.get_allocated_width ();
            int h = mochi.get_allocated_height ();
            double size = double.min (w, h) - 6;
            double breath = mood.pulses () ? 0.5 + 0.5 * Math.sin (phase * 0.35) : 0.0;
            double scale = 1.0 + 0.06 * breath;
            double cx = w / 2.0;
            double cy = h / 2.0;
            double radius = size / 2.0 * scale;

            double r, g, b;
            mood.rgb (out r, out g, out b);

            // Body: a soft squircle.
            double x = cx - radius, y = cy - radius, d = radius * 2, corner = radius * 0.62;
            cr.new_sub_path ();
            cr.arc (x + d - corner, y + corner, corner, -Math.PI / 2, 0);
            cr.arc (x + d - corner, y + d - corner, corner, 0, Math.PI / 2);
            cr.arc (x + corner, y + d - corner, corner, Math.PI / 2, Math.PI);
            cr.arc (x + corner, y + corner, corner, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
            cr.set_source_rgb (r, g, b);
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.35);
            cr.set_line_width (1);
            cr.stroke ();

            // Eyes: two dark dots; a waiting Mochi looks wide awake.
            double eye = mood == Mood.WAITING ? radius * 0.2 : radius * 0.15;
            double ey = cy - radius * 0.08;
            cr.set_source_rgb (0.07, 0.07, 0.09);
            cr.arc (cx - radius * 0.32, ey, eye, 0, 2 * Math.PI);
            cr.fill ();
            cr.arc (cx + radius * 0.32, ey, eye, 0, 2 * Math.PI);
            cr.fill ();

            // A small badge when you are needed or something went wrong.
            if (mood == Mood.WAITING || mood == Mood.ERROR) {
                cr.set_source_rgb (0, 0, 0);
                cr.arc (cx + radius * 0.95, cy - radius * 0.85, 4.2, 0, 2 * Math.PI);
                cr.fill ();
                cr.set_source_rgb (r, g, b);
                cr.arc (cx + radius * 0.95, cy - radius * 0.85, 3.2, 0, 2 * Math.PI);
                cr.fill ();
            }
            if (mood == Mood.OFF) {
                // A sleeping Mochi: the eyes are lines.
                cr.set_source_rgb (0.45, 0.46, 0.50);
            }
            return true;
        }

        // ── The panel ────────────────────────────────────────────────────────

        private string mood_text (Mood m) {
            switch (m) {
                case WORKING: return tr ("Working…", "Trabalhando…");
                case WAITING: return tr ("Waiting for you", "Esperando você");
                case FINISHED: return tr ("Finished", "Terminou");
                case ERROR: return tr ("Something went wrong", "Algo deu errado");
                case OFF: return tr ("Coucou is not running", "O Coucou não está aberto");
                default: return tr ("Nothing running", "Nada rodando");
            }
        }

        private static string clock (int64 ms) {
            if (ms <= 0) return "";
            return new DateTime.from_unix_local (ms / 1000).format ("%H:%M");
        }

        private void update_panel () {
            if (panel == null) {
                return;
            }
            headline.label = mood_text (mood);
            foreach (var child in sessions_box.get_children ()) {
                sessions_box.remove (child);
            }
            if (sessions != null) {
                uint n = uint.min (sessions.get_length (), 5);
                for (uint i = 0; i < n; i++) {
                    var s = sessions.get_object_element (i);
                    var m = Mood.parse (s.get_string_member_with_default ("state", "idle"));
                    var detail = s.get_string_member_with_default ("detail", "");
                    if (detail == "") {
                        detail = mood_text (m);
                    }
                    sessions_box.pack_start (new SessionRow (s.get_string_member_with_default ("project", ""), detail, m),
                        false, false, 0);
                }
            }
            sessions_box.show_all ();
            sessions_box.visible = sessions_box.get_children ().length () > 0;

            bool has_answer = answer_body != "";
            answer_title.visible = has_answer;
            answer_text.visible = has_answer;
            if (has_answer) {
                var when = clock (answer_at);
                answer_title.label = tr ("Last answer", "Última resposta")
                    + (answer_project != "" ? " · " + answer_project : "")
                    + (when != "" ? " · " + when : "");
                answer_text.label = answer_body;
            }
            open_button.sensitive = mood != Mood.OFF;
        }
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    // Only in the user's session, never on the login screen.
    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }
    return new Coucou.Indicator ();
}
