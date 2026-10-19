import Foundation

/// Seed content ported from the design's `store.js`. All dates are relative to today.
enum SampleData {
    static let labels: [TaskLabel] = [
        TaskLabel(id: "l1", name: "Work", hex: 0x2B7BBF, sortOrder: 0),
        TaskLabel(id: "l2", name: "Personal", hex: 0x6F8F24, sortOrder: 1),
        TaskLabel(id: "l3", name: "Health", hex: 0x1F9D8F, sortOrder: 2),
        TaskLabel(id: "l4", name: "Urgent", hex: 0xCB4733, sortOrder: 3),
        TaskLabel(id: "l5", name: "Learning", hex: 0x6A63C4, sortOrder: 4),
        TaskLabel(id: "l6", name: "Finance", hex: 0xBC8A1C, sortOrder: 5),
    ]

    static func todos() -> [Todo] {
        [
            Todo(title: "Renew domain & SSL for landing page", desc: "Auto-renew failed last year — do it manually this time and screenshot the receipt.", labelIDs: ["l1", "l6"], priority: .high, due: Day.offset(1)),
            Todo(title: "Call dentist for cleaning appointment", labelIDs: ["l3"], priority: .medium, due: Day.offset(2)),
            Todo(title: "Read 2 chapters of \u{201C}Designing Data-Intensive Apps\u{201D}", desc: "Chapters 5 & 6 — replication and partitioning.", labelIDs: ["l5"], priority: .low, due: Day.offset(4)),
            Todo(title: "Pay electricity + internet bills", desc: "Both due end of month.", labelIDs: ["l6", "l2"], priority: .high, due: Day.offset(0)),
            Todo(title: "Backup laptop to external drive", desc: "Photos folder is getting huge.", labelIDs: ["l2"], priority: .medium, due: Day.offset(6)),
            Todo(title: "Reply to mentor about portfolio review", labelIDs: ["l1", "l5"], priority: .medium, due: Day.offset(-1)),
            Todo(title: "Buy groceries for the week", desc: "Eggs, chicken, dal, veggies, oats.", labelIDs: ["l2", "l3"], priority: .low, due: Day.offset(1), done: true),
            Todo(title: "Submit reimbursement form", desc: "Conference travel — attach all receipts.", labelIDs: ["l1", "l6"], priority: .low, due: Day.offset(-2), done: true),
        ]
    }

    static func office() -> [OfficeTask] {
        [
            OfficeTask(title: "Fix production checkout bug (#1284)", refURL: URL(string: "https://github.com/acme/store/issues/1284"), due: Day.offset(0)),
            OfficeTask(title: "Prepare sprint demo for stakeholders", refURL: URL(string: "https://notion.so/acme/sprint-22-demo"), due: Day.offset(2)),
            OfficeTask(title: "Review Priya\u{2019}s API pull request", refURL: URL(string: "https://github.com/acme/api/pull/512"), due: Day.offset(1)),
            OfficeTask(title: "Update deployment runbook", refURL: URL(string: "https://confluence.acme.com/runbook"), due: Day.offset(3)),
            OfficeTask(title: "Sign off Q2 OKR document", refURL: URL(string: "https://docs.google.com/okr-q2"), due: Day.offset(-1)),
            OfficeTask(title: "Rotate API keys on staging", refURL: URL(string: "https://vault.acme.com/staging"), due: Day.offset(5), done: true),
        ]
    }

    static func university() -> University {
        let classes = [
            UniClass(id: "c1", subject: "Data Structures & Algorithms", code: "CSE 2101", days: [.sat, .tue], time: ClockTime(hour: 9, minute: 0), room: "Room 401", hex: 0x2B7BBF),
            UniClass(id: "c2", subject: "Database Systems", code: "CSE 2103", days: [.sun, .wed], time: ClockTime(hour: 11, minute: 0), room: "Lab 2", hex: 0x6F8F24),
            UniClass(id: "c3", subject: "Software Engineering", code: "CSE 2105", days: [.mon], time: ClockTime(hour: 14, minute: 0), room: "Room 305", hex: 0x6A63C4),
            UniClass(id: "c4", subject: "Linear Algebra", code: "MAT 2101", days: [.thu], time: ClockTime(hour: 10, minute: 30), room: "Room 112", hex: 0xBC8A1C),
        ]

        func topics(_ list: [(String, Bool)]) -> [SyllabusTopic] { list.map { SyllabusTopic(name: $0.0, done: $0.1) } }
        let syllabus = [
            SyllabusSubject(id: "s1", subject: "Data Structures & Algorithms", topics: topics([
                ("Arrays & Linked Lists", true), ("Stacks & Queues", true), ("Trees & BST", true),
                ("Heaps & Priority Queues", false), ("Graphs & Traversal", false), ("Dynamic Programming", false),
            ])),
            SyllabusSubject(id: "s2", subject: "Database Systems", topics: topics([
                ("Relational Model", true), ("SQL & Joins", true), ("Normalization", true),
                ("Indexing", false), ("Transactions & ACID", false),
            ])),
            SyllabusSubject(id: "s3", subject: "Software Engineering", topics: topics([
                ("SDLC Models", true), ("Requirements", true), ("UML & Design", false), ("Testing Strategies", false),
            ])),
            SyllabusSubject(id: "s4", subject: "Linear Algebra", topics: topics([
                ("Vectors & Spaces", true), ("Matrix Operations", false), ("Determinants", false), ("Eigenvalues", false),
            ])),
        ]

        let assignments = [
            Assignment(title: "DSA: Implement an AVL tree", subject: "Data Structures & Algorithms", due: Day.offset(3)),
            Assignment(title: "DB: Normalize the library schema to 3NF", subject: "Database Systems", due: Day.offset(5)),
            Assignment(title: "SE: Submit SRS document draft", subject: "Software Engineering", due: Day.offset(1)),
            Assignment(title: "Math: Problem set 4 (matrices)", subject: "Linear Algebra", due: Day.offset(-1)),
        ]

        let exams = [
            Exam(subject: "Data Structures & Algorithms", kind: .midterm, date: Day.offset(9), prep: 45),
            Exam(subject: "Database Systems", kind: .final, date: Day.offset(13), prep: 30),
            Exam(subject: "Software Engineering", kind: .classTest, date: Day.offset(5), prep: 60),
            Exam(subject: "Linear Algebra", kind: .midterm, date: Day.offset(18), prep: 15),
        ]

        return University(classes: classes, syllabus: syllabus, assignments: assignments, exams: exams)
    }

    static let universityNotes = """
        Sem 4 priorities:
        • DSA midterm is the big one — start graph problems early.
        • Ask Prof. Rahman about the DB project extension.
        • Form a study group for Linear Algebra (weakest subject).
        • Library has the 4th ed. of CLRS on reserve.
        """

    static func products() -> [Product] {
        [
            Product(id: "p1", name: "FormFlow", tagline: "No-code form builder SaaS", hex: 0xC15F3C, columns: [
                KanbanColumn(title: "Backlog", cards: [
                    KanbanCard(title: "Stripe billing integration", desc: "Metered usage + free tier cap.", labelIDs: ["l1"], priority: .medium, due: Day.offset(12)),
                    KanbanCard(title: "Dark mode for the builder", labelIDs: ["l5"], priority: .low),
                    KanbanCard(title: "Webhook delivery retries", desc: "Exponential backoff, 5 attempts.", labelIDs: ["l1"], priority: .medium, due: Day.offset(20)),
                ]),
                KanbanColumn(title: "In Progress", cards: [
                    KanbanCard(title: "Drag-and-drop field reordering", desc: "Using pointer events, no library.", labelIDs: ["l1"], priority: .high, due: Day.offset(2)),
                    KanbanCard(title: "Onboarding email sequence", desc: "3 emails over first week.", labelIDs: ["l2"], priority: .medium, due: Day.offset(4)),
                ]),
                KanbanColumn(title: "Review", cards: [
                    KanbanCard(title: "Landing page redesign", desc: "Hero + pricing + testimonials.", labelIDs: ["l1"], priority: .high, due: Day.offset(1)),
                ]),
                KanbanColumn(title: "Done", cards: [
                    KanbanCard(title: "Set up CI/CD pipeline", labelIDs: ["l1"], priority: .low, due: Day.offset(-5)),
                    KanbanCard(title: "Domain + DNS configuration", labelIDs: ["l1"], priority: .low, due: Day.offset(-8)),
                ]),
            ]),
            Product(id: "p2", name: "Pocket Recipes", tagline: "Recipe app for home cooks", hex: 0x6F8F24, columns: [
                KanbanColumn(title: "Backlog", cards: [
                    KanbanCard(title: "Grocery list auto-generation", desc: "From selected recipes.", labelIDs: ["l5"], priority: .medium),
                    KanbanCard(title: "Offline recipe caching", labelIDs: ["l1"], priority: .low),
                ]),
                KanbanColumn(title: "In Progress", cards: [
                    KanbanCard(title: "Recipe import from URL", desc: "Parse schema.org/Recipe JSON-LD.", labelIDs: ["l1"], priority: .high, due: Day.offset(6)),
                ]),
                KanbanColumn(title: "Review", cards: []),
                KanbanColumn(title: "Done", cards: [
                    KanbanCard(title: "App icon & splash screen", labelIDs: ["l2"], priority: .low, due: Day.offset(-3)),
                ]),
            ]),
        ]
    }

    static func jobStudy() -> [StudySubject] {
        func t(_ name: String, _ revisions: Int, _ daysAgo: Int?) -> StudyTopic {
            StudyTopic(name: name, revisions: revisions, lastRevised: daysAgo.map { Day.offset(-$0) })
        }
        // Staggered so the subjects keep this order (the store sorts them by creation date).
        func created(_ i: Int) -> Date { Date.now.addingTimeInterval(Double(i)) }
        return [
            StudySubject(id: "j1", subject: "System Design", hex: 0x2B7BBF, topics: [
                t("Rate limiter design", 0, nil), t("Distributed message queue", 0, nil), t("Consistent hashing", 1, 2),
                t("CAP theorem & trade-offs", 3, 1), t("Caching strategies", 2, 4), t("Load balancing basics", 5, 9),
            ], createdAt: created(0)),
            StudySubject(id: "j2", subject: "DSA", hex: 0x6A63C4, topics: [
                t("Segment trees", 0, nil), t("Dynamic programming on trees", 1, 3), t("Sliding window", 4, 1),
                t("Two pointers", 3, 2), t("Binary search variants", 6, 12),
            ], createdAt: created(1)),
            StudySubject(id: "j3", subject: "Behavioral", hex: 0x1F9D8F, topics: [
                t("Conflict with a teammate", 0, nil), t("Biggest failure", 2, 3), t("Tell me about yourself", 7, 2),
            ], createdAt: created(2)),
        ]
    }

    static func workout() -> WorkoutData {
        func day(_ label: String, _ name: String, _ sets: [String], _ tip: String) -> ProgramDay {
            ProgramDay(label: label, name: name, sets: sets, tip: tip)
        }
        func week(_ title: String, _ sub: String, milestone: String? = nil, _ d1: ProgramDay, _ d3: ProgramDay, _ d5: ProgramDay) -> ProgramWeek {
            ProgramWeek(title: title, sub: sub, milestone: milestone, days: [d1, .rest("Day 2"), d3, .rest("Day 4"), d5])
        }

        let pushupWeeks = [
            week("Wall push-ups only", "Learn the pattern, build shoulder stability",
                 day("Day 1", "Wall Push-Up", ["10 reps", "10 reps", "10 reps"], "Stand 50–60 cm from wall. Full arm extension. Chest touches wall."),
                 day("Day 3", "Wall Push-Up", ["12 reps", "12 reps", "10 reps"], "Keep your body in a straight line from head to heels."),
                 day("Day 5", "Wall Push-Up", ["15 reps", "12 reps", "12 reps"], "Rest 60 sec between sets. Too easy? Move feet farther from wall.")),
            week("Incline push-ups (high surface)", "Move to table or counter height",
                 day("Day 1", "Incline Push-Up (table)", ["8 reps", "8 reps", "6 reps"], "Sturdy table or counter. Hands shoulder-width apart."),
                 day("Day 3", "Incline Push-Up", ["10 reps", "8 reps", "8 reps"], "Lower in 2 counts, pause 1 sec, push up in 1 count."),
                 day("Day 5", "Incline Push-Up", ["12 reps", "10 reps", "10 reps"], "Core tight. Hips must not sag or pike.")),
            week("Lower the surface", "Move to chair or couch height",
                 day("Day 1", "Incline Push-Up (chair)", ["8 reps", "8 reps", "8 reps"], "Chair seat ~45 cm — noticeably harder. Expect fewer reps."),
                 day("Day 3", "Incline Push-Up (chair)", ["10 reps", "8 reps", "8 reps"], "Keep elbows at 45° from torso — not flared wide."),
                 day("Day 5", "Incline Push-Up (chair)", ["12 reps", "10 reps", "10 reps"], "When you hit 3×12 here, you’re ready for knee push-ups.")),
            week("Knee push-ups", "First time fully on the floor", milestone: "Floor milestone — you’re off the wall!",
                 day("Day 1", "Knee Push-Up", ["8 reps", "6 reps", "6 reps"], "Body straight from knees to shoulders. Don’t let hips rise."),
                 day("Day 3", "Knee Push-Up", ["10 reps", "8 reps", "8 reps"], "Full range — chest nearly touches the floor."),
                 day("Day 5", "Knee Push-Up", ["12 reps", "10 reps", "10 reps"], "Squeeze chest at the top of each rep.")),
            week("Negative full push-ups", "Lower slow, come back up on knees",
                 day("Day 1", "Negatives", ["5 reps", "5 reps", "5 reps"], "Full plank. Lower in 4–5 sec. Drop knees to push back up."),
                 day("Day 3", "Negatives", ["6 reps", "5 reps", "5 reps"], "More fatiguing than they feel. Rest 90 sec between sets."),
                 day("Day 5", "Negatives + Knee", ["Neg ×4", "Neg ×4", "Knee ×12"], "Combo: 2 sets negatives, 1 set knee push-ups for volume.")),
            week("First real push-ups", "Attempt full push-up — even 1 rep counts", milestone: "First real push-up!",
                 day("Day 1", "Full push-up attempt", ["max 1–3", "Knee ×10", "Knee ×10"], "As many full reps as possible, then drop to knees."),
                 day("Day 3", "Full + Knee combo", ["Full ×2", "Full ×2", "Knee ×12"], "Quality over quantity. A perfect 1-rep beats a sloppy 5."),
                 day("Day 5", "Full push-up test", ["AMRAP", "rest 2 min", "Knee ×15"], "Write down your max number — this is your baseline.")),
            week("Build to 3×5", "Consistency over perfection",
                 day("Day 1", "Full push-up", ["4 reps", "4 reps", "3 reps"], "Rest 90 sec. Hard but completable with good form."),
                 day("Day 3", "Full push-up", ["5 reps", "4 reps", "4 reps"], "Can’t hit target? Finish with knees. No shame."),
                 day("Day 5", "Full push-up", ["5 reps", "5 reps", "5 reps"], "3×5 full push-ups — past beginner territory!")),
            week("Push to 3×10", "The Phase 1 graduation target", milestone: "Phase 1 complete — you graduated!",
                 day("Day 1", "Full push-up", ["7 reps", "6 reps", "6 reps"], "Slow the lowering phase. Time under tension = strength."),
                 day("Day 3", "Full push-up", ["8 reps", "7 reps", "7 reps"], "Vary hand width: one wide, one narrow (tricep)."),
                 day("Day 5", "Graduation test", ["10 reps", "10 reps", "10 reps"], "Complete 3×10 and you’ve graduated Phase 1.")),
        ]

        return WorkoutData(
            streak: 5,
            history: [1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1].map { $0 == 1 },
            programs: [
                WorkoutProgram(id: "wp1", name: "Push-Up: Zero to Hero", kind: "Calisthenics",
                               desc: "8-week progressive plan — from wall push-ups to 3×10 full push-ups.",
                               hex: 0xC15F3C, daysPerWeek: 3, sessionMin: 30, completedWeeks: 3, weeks: pushupWeeks),
                WorkoutProgram(id: "wp2", name: "Core & Mobility", kind: "Flexibility",
                               desc: "Daily 15-min routine — planks, hollow holds, hip openers.",
                               hex: 0x1F9D8F, daysPerWeek: 5, sessionMin: 15, completedWeeks: 2),
                WorkoutProgram(id: "wp3", name: "Couch to 5K", kind: "Running",
                               desc: "Run/walk intervals building to a continuous 5 km.",
                               hex: 0x6A63C4, daysPerWeek: 3, sessionMin: 35, completedWeeks: 1),
            ]
        )
    }
}

// MARK: Notes

extension SampleData {
    /// Default categories. Fixed IDs and `.distantPast` stop two Macs seeding duplicates or undoing renames.
    static let noteCategories: [NoteCategory] = [
        NoteCategory(id: "nc1", name: "University", hex: 0xAF52DE, sortOrder: 0),
        NoteCategory(id: "nc2", name: "Algorithms", hex: 0x007AFF, sortOrder: 1),
        NoteCategory(id: "nc3", name: "বাংলা নোট", hex: 0xFF9500, sortOrder: 2),
        NoteCategory(id: "nc4", name: "Personal", hex: 0x34C759, sortOrder: 3),
    ]

    static func notes() -> [Note] {
        typealias B = NoteBlock
        let ago = { (hours: Double) in Date.now.addingTimeInterval(-hours * 3600) }
        func note(_ id: ID, _ category: ID, _ title: String, pinned: Bool = false, hoursAgo: Double, font: NoteFont? = nil, _ blocks: [NoteBlock]) -> Note {
            Note(id: id, categoryID: category, title: title, pinned: pinned, blocks: blocks, font: font, createdAt: ago(hoursAgo + 72), editedAt: ago(hoursAgo), updatedAt: ago(hoursAgo))
        }
        return [
            note("np1", "nc1", "Eigenvalues & Eigenvectors", pinned: true, hoursAgo: 2, [
                B(.p, #"Lecture 7 · Linear Algebra. For a square matrix $A$, a non-zero vector $\mathbf{v}$ is an **eigenvector** if multiplying by $A$ only scales it:"#),
                B(.math, #"A\mathbf{v} = \lambda \mathbf{v}, \qquad \mathbf{v} \neq \mathbf{0}"#),
                B(.h2, "Finding eigenvalues"),
                B(.p, "Solve the *characteristic equation* — its roots are the eigenvalues."),
                B(.math, #"\det(A - \lambda I) = 0"#),
                B(.h3, "Worked example"),
                B(.math, #"A = \begin{pmatrix} 2 & 1 \\ 1 & 2 \end{pmatrix} \;\Rightarrow\; \lambda^2 - 4\lambda + 3 = 0 \;\Rightarrow\; \lambda \in \{1,\, 3\}"#),
                B(.bullet, #"Sum of eigenvalues equals the trace: $\operatorname{tr}(A) = \sum_i \lambda_i$"#),
                B(.bullet, #"Product equals the determinant: $\det A = \prod_i \lambda_i$"#),
                B(.bullet, "Symmetric matrices have ==real eigenvalues== and orthogonal eigenvectors"),
                B(.h2, "Check with NumPy"),
                B(.code, "import numpy as np\n\nA = np.array([[2, 1],\n              [1, 2]])\nvals, vecs = np.linalg.eig(A)\nprint(vals)  # [3. 1.]", lang: .python),
                B(.todo, "Problem set 4 — questions 1–6", done: false),
                B(.todo, "Review proof of the spectral theorem", done: true),
            ]),
            note("np2", "nc1", "Bayes\u{2019} theorem", hoursAgo: 26, [
                B(.p, #"Update a prior belief $P(A)$ after observing evidence $B$."#),
                B(.math, #"P(A \mid B) = \frac{P(B \mid A)\,P(A)}{P(B)}"#),
                B(.quote, "The denominator is just a normaliser — expand it with the law of total probability."),
            ]),
            note("np3", "nc2", "Binary search template", pinned: true, hoursAgo: 5, [
                B(.p, #"Works on any **monotonic** predicate, not only sorted arrays. Runs in $O(\log n)$ time and $O(1)$ space."#),
                B(.code, "int lowerBound(const vector<int>& a, int target) {\n    int lo = 0, hi = a.size();\n    while (lo < hi) {\n        int mid = lo + (hi - lo) / 2;\n        if (a[mid] < target) lo = mid + 1;\n        else hi = mid;\n    }\n    return lo;  // first index with a[lo] >= target\n}", lang: .cpp),
                B(.h3, "Pitfalls"),
                B(.num, "Use `lo + (hi - lo) / 2` to avoid integer overflow"),
                B(.num, "Keep the invariant: the answer is always inside `[lo, hi]`"),
                B(.num, "Pick half-open or closed intervals ~~as you go~~ before writing code"),
                B(.quote, "If the loop can run forever, one branch isn\u{2019}t shrinking the range."),
            ]),
            note("np4", "nc2", "SQL window functions", hoursAgo: 72, [
                B(.p, "Rank rows inside a group without collapsing them like `GROUP BY` does."),
                B(.code, "SELECT name, dept, salary,\n       RANK() OVER (PARTITION BY dept ORDER BY salary DESC) AS rnk\nFROM employees\nWHERE active = TRUE;", lang: .sql),
            ]),
            note("np5", "nc3", "নিউটনের গতির সূত্র", hoursAgo: 0.66, font: NoteFont(bengali: .hind), [
                B(.p, "বল ও গতির সম্পর্ক বোঝার জন্য নিউটনের তিনটি সূত্র মৌলিক। পরীক্ষার আগে সংক্ষেপে পুনরাবৃত্তি।"),
                B(.h2, "দ্বিতীয় সূত্র"),
                B(.p, "কোনো বস্তুর ভরবেগের পরিবর্তনের হার তার উপর প্রযুক্ত বলের সমানুপাতিক। ভর স্থির থাকলে লেখা যায় $F = ma$।"),
                B(.math, #"\vec{F} = \frac{d\vec{p}}{dt} = m\,\frac{d\vec{v}}{dt}"#),
                B(.bullet, "প্রথম সূত্র — জড়তার নিয়ম"),
                B(.bullet, "দ্বিতীয় সূত্র — **বল = ভর × ত্বরণ**"),
                B(.bullet, "তৃতীয় সূত্র — প্রতিটি ক্রিয়ার সমান ও বিপরীত প্রতিক্রিয়া আছে"),
                B(.quote, "মনে রাখো: বলের একক নিউটন (N) = kg·m/s²"),
                B(.code, "# ত্বরণ নির্ণয়\ndef acceleration(force, mass):\n    return force / mass\n\nprint(acceleration(20, 4))  # 5.0", lang: .python),
                B(.todo, "অনুশীলনী ৩.২ সমাধান করা", done: false),
                B(.todo, "ল্যাব রিপোর্ট জমা দেওয়া", done: true),
            ]),
            note("np6", "nc3", "সাপ্তাহিক পরিকল্পনা", hoursAgo: 48, [
                B(.p, "এই সপ্তাহের লক্ষ্য: **তিনটি অধ্যায়** শেষ করা আর প্রতিদিন ৩০ মিনিট পড়া।"),
                B(.todo, "সোমবার — ক্যালকুলাস অনুশীলন", done: true),
                B(.todo, "বুধবার — রসায়ন ল্যাবের প্রস্তুতি", done: false),
                B(.todo, "শুক্রবার — Job Study: System Design", done: false),
            ]),
            note("np7", "nc4", "Reading list", hoursAgo: 144, [
                B(.todo, "Designing Data-Intensive Applications — ch. 5–6", done: false),
                B(.todo, "The Pragmatic Programmer", done: true),
            ]),
        ]
    }
}
