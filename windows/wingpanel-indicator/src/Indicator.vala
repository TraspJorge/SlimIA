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
        private bool blinking = false;
        private uint blink_id = 0;

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
                mochi.set_size_request (wanted_width (), 28);
                mochi.draw.connect (draw_mochi);
                // He blinks now and then; between blinks nothing is redrawn.
                blink_id = Timeout.add (3600, () => {
                    blinking = true;
                    mochi.queue_draw ();
                    Timeout.add (150, () => { blinking = false; mochi.queue_draw (); return false; });
                    return true;
                });
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
            update_size ();
            if (mochi != null) {
                mochi.queue_draw ();
                string hint = mood_text (mood);
                if (sessions != null && sessions.get_length () > 0) {
                    var detail = sessions.get_object_element (0).get_string_member_with_default ("detail", "");
                    if (detail != "") hint = hint + " · " + detail;
                }
                mochi.set_tooltip_text (hint);
            }
            update_panel ();
        }

        // ── The island in the bar ────────────────────────────────────────────
        //
        // The same look as Coucou's compact island: a black capsule, Mochi on the
        // left (soft grey body, a highlight, two dark eyes that blink), and on the
        // right a small coloured Mochi for each session.

        private const double INK_R = 0.102;
        private const double INK_G = 0.078;
        private const double INK_B = 0.071;

        private static void squircle (Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        private static void mini_rgb (Mood m, out double r, out double g, out double b) {
            switch (m) {
                case Mood.WORKING: r = 0.231; g = 0.620; b = 1.000; break;
                case Mood.WAITING: r = 0.961; g = 0.647; b = 0.141; break;
                case Mood.FINISHED: r = 0.204; g = 0.827; b = 0.600; break;
                case Mood.ERROR: r = 0.957; g = 0.314; b = 0.369; break;
                default: r = 0.54; g = 0.56; b = 0.60; break;
            }
        }

        private double mochi_radius (double capsule_h) {
            return capsule_h * 0.37;
        }

        private int session_count () {
            return sessions == null ? 0 : (int) uint.min (sessions.get_length (), 4);
        }

        private int wanted_width () {
            double r = mochi_radius (24);
            double w = 7 + r * 2 * 1.12 + 7;
            int n = session_count ();
            if (n > 0) {
                int cols = n > 2 ? 2 : n;
                w += 5 + cols * 8 + (cols - 1) * 3;
            }
            return (int) Math.ceil (w);
        }

        private void update_size () {
            if (mochi != null) {
                mochi.set_size_request (wanted_width (), 28);
            }
        }

        private void paint_mochi (Cairo.Context cr, double cx, double cy, double R) {
            double breath = mood.pulses () ? 0.5 + 0.5 * Math.sin (phase * 0.35) : 0.0;
            double sc = 1.0 + 0.05 * breath;
            double rw = R * 1.12 * sc;
            double rh = R * 0.98 * sc;
            double alpha = mood == Mood.OFF ? 0.5 : 1.0;

            cr.save ();
            squircle (cr, cx - rw, cy - rh, rw * 2, rh * 2, rh * 0.84);
            cr.clip ();

            var body = new Cairo.Pattern.linear (cx + rw * 0.7, cy - rh * 0.85, cx - rw * 0.8, cy + rh * 0.9);
            body.add_color_stop_rgba (0, 0.929, 0.929, 0.937, alpha);
            body.add_color_stop_rgba (1, 0.769, 0.773, 0.792, alpha);
            cr.set_source (body);
            cr.paint ();

            // The colour of what is going on rises from the bottom, like Mochi's tint.
            double strength = 0;
            switch (mood) {
                case Mood.WORKING: strength = 0.45 + 0.35 * breath; break;
                case Mood.WAITING: strength = 0.6 + 0.3 * breath; break;
                case Mood.FINISHED: strength = 0.6; break;
                case Mood.ERROR: strength = 0.7; break;
                default: break;
            }
            if (strength > 0) {
                double tr_, tg, tb;
                mood.rgb (out tr_, out tg, out tb);
                var tint = new Cairo.Pattern.linear (0, cy + rh, 0, cy - rh);
                tint.add_color_stop_rgba (0, tr_, tg, tb, 0.85 * strength);
                tint.add_color_stop_rgba (1, tr_, tg, tb, 0);
                cr.set_source (tint);
                cr.paint ();
            }

            var shade = new Cairo.Pattern.radial (cx, cy, R * 0.15, cx, cy, R * 1.25);
            shade.add_color_stop_rgba (0, 0, 0, 0, 0);
            shade.add_color_stop_rgba (0.6, 0, 0, 0, 0);
            shade.add_color_stop_rgba (1, 0, 0, 0, 0.2);
            cr.set_source (shade);
            cr.paint ();

            var light = new Cairo.Pattern.radial (cx + rw * 0.34, cy - rh * 0.46, 0, cx + rw * 0.34, cy - rh * 0.46, R * 0.42);
            light.add_color_stop_rgba (0, 1, 1, 1, 0.55 * alpha * alpha);
            light.add_color_stop_rgba (1, 1, 1, 1, 0);
            cr.set_source (light);
            cr.paint ();
            cr.restore ();

            // Eyes.
            double ex = R * 0.37;
            double ey = cy - R * 0.12;
            double look = mood == Mood.WORKING ? Math.sin (phase * 0.22) * R * 0.14 : 0.0;
            cr.set_source_rgba (INK_R, INK_G, INK_B, alpha);
            if (mood == Mood.OFF) {
                cr.set_line_width (1.2);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.move_to (cx + sd * ex - R * 0.13, ey + R * 0.04);
                    cr.line_to (cx + sd * ex + R * 0.13, ey + R * 0.04);
                    cr.stroke ();
                }
            } else if (mood == Mood.FINISHED) {
                cr.set_line_width (1.4);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.new_sub_path ();
                    cr.arc (cx + sd * ex, ey + R * 0.1, R * 0.17, Math.PI, 2 * Math.PI);
                    cr.stroke ();
                }
            } else {
                double erx = mood == Mood.WAITING ? R * 0.17 : R * 0.14;
                double ery = (mood == Mood.WAITING ? R * 0.27 : R * 0.21) * (blinking ? 0.12 : 1.0);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.save ();
                    cr.translate (cx + sd * ex + look, ey);
                    cr.scale (erx, ery);
                    cr.arc (0, 0, 1, 0, 2 * Math.PI);
                    cr.restore ();
                    cr.fill ();
                }
            }

            // The badge Mochi wears when you are needed, or when something broke.
            if (mood == Mood.WAITING || mood == Mood.ERROR) {
                double br, bg, bb;
                mood.rgb (out br, out bg, out bb);
                cr.set_source_rgb (0, 0, 0);
                cr.arc (cx + rw * 0.92, cy - rh * 0.9, 3.6, 0, 2 * Math.PI);
                cr.fill ();
                cr.set_source_rgb (br, bg, bb);
                cr.arc (cx + rw * 0.92, cy - rh * 0.9, 2.7, 0, 2 * Math.PI);
                cr.fill ();
            }
        }

        private void paint_mini (Cairo.Context cr, double x, double y, Mood m) {
            double r, g, b;
            mini_rgb (m, out r, out g, out b);
            squircle (cr, x, y, 8, 7, 2.8);
            cr.set_source_rgb (r, g, b);
            cr.fill ();
            cr.set_source_rgb (0.063, 0.075, 0.102);
            cr.arc (x + 2.6, y + 3.1, 0.85, 0, 2 * Math.PI);
            cr.fill ();
            cr.arc (x + 5.4, y + 3.1, 0.85, 0, 2 * Math.PI);
            cr.fill ();
        }

        private bool draw_mochi (Cairo.Context cr) {
            int w = mochi.get_allocated_width ();
            int h = mochi.get_allocated_height ();
            double ch = double.min (h - 4.0, 24.0);
            double top = (h - ch) / 2.0;
            double mid = h / 2.0;
            double width = double.min (w - 1.0, wanted_width () - 1.0);
            double x0 = (w - width) / 2.0;

            // The capsule: black, with the faintest rim.
            squircle (cr, x0, top, width, ch, ch / 2.0);
            cr.set_source_rgb (0, 0, 0);
            cr.fill_preserve ();
            cr.set_source_rgba (1, 1, 1, 0.1);
            cr.set_line_width (1);
            cr.stroke ();

            double R = mochi_radius (ch);
            paint_mochi (cr, x0 + 7 + R * 1.12, mid, R);

            int n = session_count ();
            if (n > 0) {
                int cols = n > 2 ? 2 : n;
                int rows = n > 2 ? 2 : 1;
                double gx = x0 + 7 + R * 2 * 1.12 + 5;
                double gy = mid - (rows * 7 + (rows - 1) * 3) / 2.0;
                for (int i = 0; i < n; i++) {
                    var s = sessions.get_object_element (i);
                    var m = Mood.parse (s.get_string_member_with_default ("state", "idle"));
                    paint_mini (cr, gx + (i % cols) * 11, gy + (i / cols) * 10, m);
                }
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
