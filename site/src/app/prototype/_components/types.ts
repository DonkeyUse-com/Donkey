import type { Dispatch, RefObject, SetStateAction } from 'react';

export type TaskId = 'compare' | 'research' | 'reply' | 'schedule' | 'update';

export type NotchState =
  | 'idle'
  | 'running-single'
  | 'running-multi'
  | 'complete'
  | 'needs-input'
  | 'expanded-pinned';

export type TaskSample = {
  id: TaskId;
  label: string;
  color: string;
  detail: string;
};

export type Point = {
  x: number;
  y: number;
};

export type DesktopSize = {
  w: number;
  h: number;
};

export type SpawnPhase = 'notch-cue' | 'traveling' | 'holding' | 'fading';

export type Spawn = {
  id: string;
  taskId: string;
  color: string;
  label: string;
  target: Point;
  phase: SpawnPhase;
  notchCueAngleDegrees: number;
  startedAt: number;
};

export type SetHovering = Dispatch<SetStateAction<boolean>>;

export type DesktopRef = RefObject<HTMLDivElement | null>;
