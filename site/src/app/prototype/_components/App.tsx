'use client';

import { type FormEvent, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import { DemoControls } from '@/app/prototype/_components/DemoControls';
import { MacDesktop } from '@/app/prototype/_components/MacDesktop';
import { TASK_COLORS } from '@/app/prototype/_components/tasks';
import type { DesktopSize, NotchState, Spawn, SpawnPhase, TaskId } from '@/app/prototype/_components/types';

const COMPOSER_TEXT_MIN_HEIGHT = 19.2;
const COMPOSER_TEXT_MAX_HEIGHT = 134.4;
const COLLAPSED_NOTCH_VISIBLE_HEIGHT = 32;
const SPAWN_FALLBACK_VERTICAL_OFFSET = 250;
const SPAWN_SCREEN_INSET = 36;
const SPAWN_NOTCH_CUE_DURATION_MS = 260;
const SPAWN_TRAVEL_DURATION_MS = 820;

function clampedSpawnPoint(x: number, y: number, desktopSize: DesktopSize) {
  return {
    x: Math.min(Math.max(x, SPAWN_SCREEN_INSET), Math.max(SPAWN_SCREEN_INSET, desktopSize.w - SPAWN_SCREEN_INSET)),
    y: Math.min(Math.max(y, SPAWN_SCREEN_INSET), Math.max(SPAWN_SCREEN_INSET, desktopSize.h - SPAWN_SCREEN_INSET)),
  };
}

function fallbackSpawnTarget(desktopSize: DesktopSize, spawnIndex: number) {
  const stagger = ((spawnIndex % 5) - 2) * 18;

  return clampedSpawnPoint(
    desktopSize.w / 2 + stagger,
    COLLAPSED_NOTCH_VISIBLE_HEIGHT + SPAWN_FALLBACK_VERTICAL_OFFSET,
    desktopSize,
  );
}

export default function App() {
  const [state, setState] = useState<NotchState>('running-single');
  const [activeTaskId, setActiveTaskId] = useState<TaskId>('compare');
  const [notchExpanded, setNotchExpanded] = useState(false);
  const [promptText, setPromptText] = useState('');
  const [promptTextHeight, setPromptTextHeight] = useState(COMPOSER_TEXT_MIN_HEIGHT);
  const [spawns, setSpawns] = useState<Spawn[]>([]);
  const [selectedSpawnId, setSelectedSpawnId] = useState<string | null>(null);
  const [editingSpawnId, setEditingSpawnId] = useState<string | null>(null);
  const [desktopSize, setDesktopSize] = useState<DesktopSize>({ w: 1280, h: 720 });
  const promptInputRef = useRef<HTMLTextAreaElement | null>(null);
  const desktopRef = useRef<HTMLElement | null>(null);
  const spawnCounterRef = useRef(0);
  const spawnTimerRef = useRef<number[]>([]);

  useLayoutEffect(() => {
    const input = promptInputRef.current;
    if (!input) return;

    input.style.height = 'auto';
    const nextHeight = Math.min(
      Math.max(Math.ceil(input.scrollHeight), COMPOSER_TEXT_MIN_HEIGHT),
      COMPOSER_TEXT_MAX_HEIGHT,
    );
    input.style.height = `${nextHeight}px`;
    setPromptTextHeight(nextHeight);
  }, [promptText]);

  const promptExpanded =
    promptText.trim().length > 0 &&
    (promptTextHeight > COMPOSER_TEXT_MIN_HEIGHT + 1 || promptText.includes('\n'));

  useLayoutEffect(() => {
    const desktop = desktopRef.current;
    if (!desktop) return;

    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (!rect) return;

      setDesktopSize({ w: rect.width, h: rect.height });
    });
    observer.observe(desktop);

    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    return () => {
      spawnTimerRef.current.forEach((timer) => window.clearTimeout(timer));
      spawnTimerRef.current = [];
    };
  }, []);

  const advanceSpawn = useCallback((id: string, nextPhase: SpawnPhase) => {
    setSpawns((current) => current.map((spawn) => (spawn.id === id ? { ...spawn, phase: nextPhase } : spawn)));
  }, []);

  const scheduleSpawnPhase = useCallback((id: string, nextPhase: SpawnPhase, delay: number) => {
    const timer = window.setTimeout(() => advanceSpawn(id, nextPhase), delay);
    spawnTimerRef.current.push(timer);
  }, [advanceSpawn]);

  const handleSpawn = useCallback((taskText: string) => {
    const spawnIndex = spawnCounterRef.current;
    spawnCounterRef.current += 1;
    const id = `spawn-${spawnCounterRef.current}-${Date.now()}`;
    const color = TASK_COLORS[spawnIndex % TASK_COLORS.length];
    const target = fallbackSpawnTarget(desktopSize, spawnIndex);

    setSpawns((current) => [
      ...current,
      {
        id,
        taskId: id,
        color,
        label: taskText,
        target,
        phase: 'notch-cue',
        notchCueAngleDegrees: 90,
        startedAt: Date.now(),
      },
    ]);
    setSelectedSpawnId(id);
    setEditingSpawnId(null);

    scheduleSpawnPhase(id, 'traveling', SPAWN_NOTCH_CUE_DURATION_MS);
    scheduleSpawnPhase(id, 'holding', SPAWN_NOTCH_CUE_DURATION_MS + SPAWN_TRAVEL_DURATION_MS);
  }, [desktopSize, scheduleSpawnPhase]);

  const handleSpawnFollowUp = useCallback((spawnId: string, text: string) => {
    const label = text.trim();
    if (!label) return;

    setSpawns((current) =>
      current.map((spawn) =>
        spawn.id === spawnId
          ? {
              ...spawn,
              label,
              phase: 'holding',
              startedAt: Date.now(),
            }
          : spawn,
      ),
    );
    setSelectedSpawnId(spawnId);
    setEditingSpawnId(null);
  }, []);

  const handleSubmit = useCallback((event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    const taskText = promptText.trim();
    if (!taskText) return;

    handleSpawn(taskText);
    setPromptText('');
    promptInputRef.current?.focus();
  }, [handleSpawn, promptText]);

  const isNotchExpanded = notchExpanded || state === 'expanded-pinned';

  return (
    <div className="relative min-h-screen">
      <MacDesktop
        state={state}
        activeTaskId={activeTaskId}
        notchExpanded={isNotchExpanded}
        setNotchExpanded={setNotchExpanded}
        promptText={promptText}
        setPromptText={setPromptText}
        promptInputRef={promptInputRef}
        promptTextHeight={promptTextHeight}
        promptExpanded={promptExpanded}
        onPromptSubmit={handleSubmit}
        desktopRef={desktopRef}
        desktopSize={desktopSize}
        spawns={spawns}
        selectedSpawnId={selectedSpawnId}
        editingSpawnId={editingSpawnId}
        setSelectedSpawnId={setSelectedSpawnId}
        setEditingSpawnId={setEditingSpawnId}
        onSpawnFollowUp={handleSpawnFollowUp}
        onRequestSpawn={handleSpawn}
      />
      <DemoControls
        state={state}
        setState={setState}
        activeTaskId={activeTaskId}
        setActiveTaskId={setActiveTaskId}
        spawnCount={spawns.length}
        onClearSpawns={() => {
          setSpawns([]);
          setSelectedSpawnId(null);
          setEditingSpawnId(null);
        }}
      />
    </div>
  );
}
