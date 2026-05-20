'use client';

import { type FormEvent, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import { DemoControls } from '@/app/prototype/_components/DemoControls';
import { MacDesktop } from '@/app/prototype/_components/MacDesktop';
import { TASK_COLORS } from '@/app/prototype/_components/tasks';
import type { DesktopSize, NotchState, Spawn, SpawnPhase, TaskId } from '@/app/prototype/_components/types';

const COMPOSER_TEXT_MIN_HEIGHT = 19.2;
const COMPOSER_TEXT_MAX_HEIGHT = 134.4;

export default function App() {
  const [state, setState] = useState<NotchState>('running-single');
  const [activeTaskId, setActiveTaskId] = useState<TaskId>('compare');
  const [notchExpanded, setNotchExpanded] = useState(false);
  const [promptText, setPromptText] = useState('');
  const [promptTextHeight, setPromptTextHeight] = useState(COMPOSER_TEXT_MIN_HEIGHT);
  const [spawns, setSpawns] = useState<Spawn[]>([]);
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
    spawnCounterRef.current += 1;
    const id = `spawn-${spawnCounterRef.current}-${Date.now()}`;
    const color = TASK_COLORS[spawnCounterRef.current % TASK_COLORS.length];
    const label = taskText.slice(0, 40);
    const padding = 60;
    const targetX = padding + Math.random() * Math.max(1, desktopSize.w - padding * 2);
    const targetY = 90 + Math.random() * Math.max(1, desktopSize.h - 160);
    const curveSide = Math.random() > 0.5 ? 1 : -1;

    setSpawns((current) => [
      ...current,
      {
        id,
        color,
        label,
        target: { x: targetX, y: targetY },
        phase: 'travel',
        curveSide,
        startedAt: Date.now(),
      },
    ]);

    scheduleSpawnPhase(id, 'shake-left', 900);
    scheduleSpawnPhase(id, 'shake-right', 1250);
    scheduleSpawnPhase(id, 'working', 1600);
  }, [desktopSize.h, desktopSize.w, scheduleSpawnPhase]);

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
        onRequestSpawn={handleSpawn}
      />
      <DemoControls
        state={state}
        setState={setState}
        activeTaskId={activeTaskId}
        setActiveTaskId={setActiveTaskId}
        spawnCount={spawns.length}
        onClearSpawns={() => setSpawns([])}
      />
    </div>
  );
}
