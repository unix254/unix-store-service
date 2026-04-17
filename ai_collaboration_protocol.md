# AI Collaboration Protocol

This document outlines the strict operational rules for how Gemini and Claude coordinate to build, maintain, and manage the `unix-store-service` ecosystem. Gemini acts as the product brain, architect, tester, and environment manager. Claude acts as the primary code implementer inside the local editor.

## The Instructions Workflow

**Rule 1: Always Use `claude_instructions.md`**
- Gemini must **always** write task requirements and phase guidelines directly to `claude_instructions.md` in the project root.
- **NEVER** create separate iteration files (e.g., *never* `claude_phase16_instructions.md`, `claude_instructions_v2.md`, etc.). 
- If a new phase is starting, overwrite the existing `claude_instructions.md` with the new phase instructions.

**Rule 2: Always Use `claude_feedback.md`**
- Claude must **always** write their completion summary, architectural decisions, and specific feedback to `claude_feedback.md`.
- Gemini reads `claude_feedback.md` to verify completion and to understand changes before running environments, deployments, or tests.

## Why this Structure?
It keeps the project root clean, establishes a predictable two-way communication channel, and ensures context isn't lost or fragmented across dozens of randomly numbered markdown files.
