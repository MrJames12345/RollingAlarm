-- Migration: Rename/convert SnoozeMinutes to SnoozeSeconds
ALTER TABLE routines ADD COLUMN snooze_seconds INTEGER NOT NULL DEFAULT 300;
UPDATE routines SET snooze_seconds = snooze_minutes * 60;
