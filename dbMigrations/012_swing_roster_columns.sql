-- Migration v19: FIFO & nursing swing-roster cycle columns on routines
ALTER TABLE routines ADD COLUMN cycle_on_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE routines ADD COLUMN cycle_off_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE routines ADD COLUMN cycle_anchor_epoch_day INTEGER NULL;
