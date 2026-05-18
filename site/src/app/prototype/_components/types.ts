import type { Dispatch, RefObject, SetStateAction } from 'react';
import type { LucideIcon } from 'lucide-react';

export type AgentId = 'coder' | 'browser' | 'researcher' | 'inbox' | 'scheduler';

export type NotchState =
  | 'idle'
  | 'running-single'
  | 'running-multi'
  | 'complete'
  | 'needs-input'
  | 'expanded-pinned';

export type Agent = {
  id: AgentId;
  name: string;
  color: string;
  Icon: LucideIcon;
  subtitle: string;
};

export type Point = {
  x: number;
  y: number;
};

export type DesktopSize = {
  w: number;
  h: number;
};

export type SpawnPhase = 'emerge' | 'travel' | 'shake-left' | 'shake-right' | 'working';

export type Spawn = {
  id: string;
  color: string;
  label: string;
  target: Point;
  phase: SpawnPhase;
  curveSide: 1 | -1;
  startedAt: number;
};

export type SetHovering = Dispatch<SetStateAction<boolean>>;

export type DesktopRef = RefObject<HTMLDivElement | null>;
