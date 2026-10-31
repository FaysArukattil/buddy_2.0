# 🚀 Buddy Agent Handoff System

**Read this file first, then the following in order:**

1. **[PROJECT_CONTEXT.md](./PROJECT_CONTEXT.md)** — What Buddy is, tech stack, folder structure, key files, how SMS parsing works, how the app is built/released.
2. **[TASKS.md](./TASKS.md)** — Checklist of every task and sub-task with status.
3. **[HANDOFF.md](./HANDOFF.md)** — Latest state: what was being done, what's half-done, exact next step, known bugs.
4. **[DECISIONS.md](./DECISIONS.md)** — Log of each design decision with reasoning.
5. **[PARSING_RESEARCH.md](./PARSING_RESEARCH.md)** — Bank SMS format research per country/region.

---

## Working Rules (MANDATORY)

1. **After EVERY completed sub-task:**
   - ✅ Tick it in `TASKS.md` (change `[ ]` → `[x]`, add file paths touched)
   - ✅ Update `HANDOFF.md` with current state
   - ✅ Make a small git commit with a clear message

2. **Before touching code**, always:
   - Run `flutter analyze` to verify the current state
   - Check `TASKS.md` to see what's already done
   - Read `HANDOFF.md` for context on what's in progress

3. **If you are near a limit**, STOP and write `HANDOFF.md` in full detail first, before doing anything else.

4. **After each task**, run `flutter analyze` and the test suite. Do not leave the build broken.

5. **Existing users are on the Play Store.** Nothing may break for them. Default existing users to India/INR. Do not rewrite working Indian SMS parsing without regression tests first.

6. **Order of work:** Step 0 (docs) → Task 1 (update prompt) → Task 2 (currency: B,C,D then A) → Task 3 (parsing research → parser refactor + tests)
