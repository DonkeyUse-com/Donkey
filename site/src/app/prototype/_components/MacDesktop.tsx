import type { FormEvent, RefObject } from 'react';

import { Notch } from '@/app/prototype/_components/Notch';
import { SpawnedCursor } from '@/app/prototype/_components/SpawnedCursor';
import type { DesktopSize, NotchState, Spawn, TaskId } from '@/app/prototype/_components/types';

type Props = {
  state: NotchState;
  activeTaskId: TaskId;
  notchExpanded: boolean;
  setNotchExpanded: (expanded: boolean) => void;
  promptText: string;
  setPromptText: (text: string) => void;
  promptInputRef: RefObject<HTMLTextAreaElement | null>;
  promptTextHeight: number;
  promptExpanded: boolean;
  onPromptSubmit: (event: FormEvent<HTMLFormElement>) => void;
  desktopRef: RefObject<HTMLElement | null>;
  desktopSize: DesktopSize;
  spawns: Spawn[];
  onRequestSpawn: (taskText: string) => void;
};

const LAYOUT = {
  contentWidth: 592,
  contentExtraHeight: 8,
  stageHorizontalPadding: 8,
  stageVerticalPadding: 10,
  composerWidth: 576,
  composerCornerRadius: 22,
  composerInputMinimumHeight: 66,
  composerInputLeadingContentPadding: 20,
  composerInputTrailingContentPadding: 8,
  composerWaveformWidth: 54,
  composerWaveformHeight: 28,
  composerWrappingTextWidth: 482,
  composerExpandedTextWidth: 528,
  composerExpandedTextTopPadding: 18,
  composerExpandedTextHorizontalPadding: 24,
  composerExpandedToolbarHeight: 54,
  composerExpandedMinimumHeight: 156,
} as const;

const WAVEFORM_LEVELS = [0.12, 0.2, 0.34, 0.5, 0.34, 0.2, 0.12] as const;

function waveformHeight(level: number) {
  return 5 + level * 24;
}

export function MacDesktop({
  state,
  activeTaskId,
  notchExpanded,
  setNotchExpanded,
  promptText,
  setPromptText,
  promptInputRef,
  promptTextHeight,
  promptExpanded,
  onPromptSubmit,
  desktopRef,
  desktopSize,
  spawns,
  onRequestSpawn,
}: Props) {
  const composerHeight = promptExpanded
    ? Math.max(
        LAYOUT.composerExpandedMinimumHeight,
        promptTextHeight + LAYOUT.composerExpandedTextTopPadding + LAYOUT.composerExpandedToolbarHeight,
      )
    : LAYOUT.composerInputMinimumHeight;
  const hostHeight = LAYOUT.stageVerticalPadding * 2 + composerHeight + LAYOUT.contentExtraHeight;
  const spawnOrigin = { x: desktopSize.w / 2, y: -36 };

  return (
    <main
      ref={desktopRef}
      className="relative min-h-screen overflow-hidden bg-[#121419] text-white"
      style={{ fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif' }}
    >
      <div
        className="absolute inset-0"
        style={{
          background:
            'linear-gradient(145deg, rgba(44,66,78,0.82) 0%, rgba(20,21,26,0.96) 45%, rgba(33,36,51,0.92) 100%)',
        }}
      />
      <div
        className="absolute inset-0"
        style={{
          background:
            'linear-gradient(180deg, rgba(0,0,0,0.18) 0%, rgba(0,0,0,0) 26%, rgba(0,0,0,0.32) 100%)',
        }}
      />

      <div
        className="absolute left-0 right-0 top-0 z-10 flex h-7 items-center gap-4 px-4 text-[13px] text-white/[0.72]"
        style={{
          background: 'rgba(11,12,15,0.55)',
          backdropFilter: 'blur(14px)',
        }}
      >
        <span className="font-medium text-white/[0.88]">Donkey</span>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
        <span>Go</span>
        <span>Window</span>
        <span>Help</span>
      </div>

      <Notch
        state={state}
        activeTaskId={activeTaskId}
        expanded={notchExpanded}
        setExpanded={setNotchExpanded}
        onRequestSpawn={onRequestSpawn}
      />

      {spawns.map((spawn) => (
        <SpawnedCursor key={spawn.id} spawn={spawn} spawnOrigin={spawnOrigin} />
      ))}

      <section
        aria-label="Donkey prompt"
        className="absolute left-1/2 top-1/2 z-20"
        style={{
          width: LAYOUT.contentWidth,
          height: hostHeight,
          padding: `${LAYOUT.stageVerticalPadding}px ${LAYOUT.stageHorizontalPadding}px`,
          transform: 'translate(-50%, -50%)',
        }}
      >
        <form
          onSubmit={onPromptSubmit}
          className="relative bg-black"
          style={{
            width: LAYOUT.composerWidth,
            height: composerHeight,
            borderRadius: promptExpanded ? LAYOUT.composerCornerRadius : 999,
            boxShadow: `0 5px 12px rgba(0,0,0,0.2), inset 0 0 0 1px ${
              promptExpanded ? 'rgba(255,255,255,0.28)' : 'rgba(255,255,255,0.34)'
            }`,
            transition: 'height 160ms ease-out, border-radius 160ms ease-out',
          }}
        >
          <label className="sr-only" htmlFor="donkey-prompt-input">
            Prompt
          </label>
          <textarea
            id="donkey-prompt-input"
            ref={promptInputRef}
            rows={1}
            value={promptText}
            onChange={(event) => setPromptText(event.target.value)}
            placeholder="What can donkey do for you?"
            className="absolute resize-none overflow-hidden border-0 bg-transparent p-0 text-[16px] font-light leading-[19.2px] text-white outline-none placeholder:text-white/[0.58]"
            style={{
              left: promptExpanded
                ? LAYOUT.composerExpandedTextHorizontalPadding
                : LAYOUT.composerInputLeadingContentPadding,
              top: promptExpanded
                ? LAYOUT.composerExpandedTextTopPadding
                : (LAYOUT.composerInputMinimumHeight - promptTextHeight) / 2,
              width: promptExpanded ? LAYOUT.composerExpandedTextWidth : LAYOUT.composerWrappingTextWidth,
              height: promptTextHeight,
              caretColor: 'white',
              fontVariantLigatures: 'none',
            }}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                event.currentTarget.form?.requestSubmit();
              }
            }}
          />
          <div
            className="absolute flex items-center justify-center gap-1"
            style={{
              right: promptExpanded
                ? LAYOUT.composerExpandedTextHorizontalPadding
                : LAYOUT.composerInputTrailingContentPadding,
              top: promptExpanded
                ? composerHeight - LAYOUT.composerExpandedToolbarHeight + (LAYOUT.composerExpandedToolbarHeight - LAYOUT.composerWaveformHeight) / 2
                : (LAYOUT.composerInputMinimumHeight - LAYOUT.composerWaveformHeight) / 2,
              width: LAYOUT.composerWaveformWidth,
              height: LAYOUT.composerWaveformHeight,
            }}
            aria-hidden="true"
          >
            {WAVEFORM_LEVELS.map((level, index) => (
              <span
                key={`${level}-${index}`}
                className="w-1 rounded-full bg-white"
                style={{ height: waveformHeight(level) }}
              />
            ))}
          </div>
        </form>
      </section>
    </main>
  );
}
