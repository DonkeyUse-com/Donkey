import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { CSSProperties, KeyboardEvent } from 'react';

import { DonkeyCursor } from '@/app/prototype/_components/DonkeyCursor';
import type { DesktopSize, Point, Spawn } from '@/app/prototype/_components/types';

type Props = {
  spawn: Spawn;
  spawnOrigin: Point;
  desktopSize: DesktopSize;
  selected: boolean;
  editing: boolean;
  onSelect: () => void;
  onBeginEditing: () => void;
  onCancelEditing: () => void;
  onSubmitFollowUp: (text: string) => void;
};

type MotionPathStyle = CSSProperties & {
  WebkitOffsetPath?: string;
  WebkitOffsetRotate?: string;
};

const TRAVEL_DURATION_MS = 820;
const CURSOR_BASE_ROTATION_DEG = 50;
const COLLAPSED_LABEL_WIDTH = 260;
const COLLAPSED_LABEL_CONTENT_WIDTH = 240;
const COLLAPSED_LABEL_BOTTOM_GAP = 22;
const EXPANDED_LABEL_CONTENT_WIDTH = 480;
const LABEL_HORIZONTAL_PADDING = 10;
const LABEL_VERTICAL_PADDING = 5;
const LABEL_FONT_SIZE = 12;
const LABEL_LINE_HEIGHT = 14;
const COLLAPSED_LABEL_APPROX_CHARS_PER_LINE = 40;
const INLINE_EDITOR_CONTENT_WIDTH = 480;
const INLINE_EDITOR_INPUT_HEIGHT = 64;
const INLINE_EDITOR_HORIZONTAL_PADDING = 16;
const INLINE_EDITOR_VERTICAL_PADDING = 14;
const INLINE_EDITOR_SPACING = 12;
const INLINE_EDITOR_MIN_TEXT_HEIGHT = 14;
const INLINE_EDITOR_MAX_TEXT_HEIGHT = 44;
const HALO_VERTICAL_OFFSET = 12;

const INPUT_ACCENT_BY_COLOR: Record<string, string> = {
  '#1D9E75': '#B0DECF',
  '#EF9F27': '#FADEB3',
  '#D4537E': '#F0C4D1',
  '#378ADD': '#BAD6F2',
  '#7F77DD': '#D4CFF2',
  '#E15A47': '#F5C4BF',
  '#3DB0B5': '#BAE3E6',
  '#A856C9': '#E0C4ED',
};

function useTypewriterText(text: string, identity: string) {
  const [visibleText, setVisibleText] = useState('');

  useEffect(() => {
    const characters = Array.from(text);
    const resetTimer = window.setTimeout(() => setVisibleText(''), 0);
    if (characters.length === 0) {
      return () => window.clearTimeout(resetTimer);
    }

    const timers = characters.map((_, index) =>
      window.setTimeout(() => {
        setVisibleText(characters.slice(0, index + 1).join(''));
      }, (index + 1) * 26),
    );

    return () => {
      window.clearTimeout(resetTimer);
      timers.forEach((timer) => window.clearTimeout(timer));
    };
  }, [identity, text]);

  return visibleText;
}

function textCharacterCount(text: string) {
  return Math.max(Array.from(text.trim()).length, 1);
}

function collapsedLabelNeedsExpansion(text: string) {
  return text.includes('\n') || textCharacterCount(text) > 78;
}

function collapsedLabelHeight(text: string) {
  const lineCount = Math.min(
    Math.max(Math.ceil(textCharacterCount(text) / COLLAPSED_LABEL_APPROX_CHARS_PER_LINE), 1),
    2,
  );

  return lineCount * LABEL_LINE_HEIGHT + LABEL_VERTICAL_PADDING * 2;
}

function expandedLabelHeight(text: string) {
  const lineCount = Math.max(1, Math.ceil(textCharacterCount(text) / 44));

  return Math.max(collapsedLabelHeight(text), lineCount * LABEL_LINE_HEIGHT + LABEL_VERTICAL_PADDING * 2);
}

function inlineEditorMessageHeight(text: string) {
  const lineCount = Math.min(Math.max(Math.ceil(textCharacterCount(text) / 64), 1), 3);

  return lineCount * 14 + 6;
}

function inlineEditorSize(text: string) {
  return {
    width: INLINE_EDITOR_CONTENT_WIDTH + INLINE_EDITOR_HORIZONTAL_PADDING * 2,
    height:
      inlineEditorMessageHeight(text) +
      INLINE_EDITOR_SPACING +
      INLINE_EDITOR_INPUT_HEIGHT +
      INLINE_EDITOR_VERTICAL_PADDING * 2,
  };
}

function pointFits(point: Point, offset: Point, labelSize: { width: number; height: number }, desktopSize: DesktopSize) {
  const margin = 20;
  const minX = point.x + offset.x - labelSize.width / 2;
  const minY = point.y + offset.y - labelSize.height / 2;
  const maxX = minX + labelSize.width;
  const maxY = minY + labelSize.height;

  return minX >= margin && minY >= margin && maxX <= desktopSize.w - margin && maxY <= desktopSize.h - margin;
}

function labelOffset(point: Point, labelSize: { width: number; height: number }, desktopSize: DesktopSize) {
  const preferred = { x: 0, y: -(labelSize.height / 2 + COLLAPSED_LABEL_BOTTOM_GAP) };
  const left = { x: -(labelSize.width / 2 + 44), y: 0 };
  const right = { x: labelSize.width / 2 + 44, y: 0 };
  const below = { x: 0, y: labelSize.height / 2 + 44 };

  if (pointFits(point, preferred, labelSize, desktopSize)) return preferred;
  if (pointFits(point, left, labelSize, desktopSize)) return left;
  if (pointFits(point, right, labelSize, desktopSize)) return right;

  return below;
}

function inputAccentColor(color: string) {
  return INPUT_ACCENT_BY_COLOR[color.toUpperCase()] ?? 'rgba(255,255,255,0.72)';
}

export function SpawnedCursor({
  spawn,
  spawnOrigin,
  desktopSize,
  selected,
  editing,
  onSelect,
  onBeginEditing,
  onCancelEditing,
  onSubmitFollowUp,
}: Props) {
  const { id, color, label, target, phase } = spawn;
  const [labelHovered, setLabelHovered] = useState(false);
  const [draftText, setDraftText] = useState('');
  const [draftTextHeight, setDraftTextHeight] = useState(INLINE_EDITOR_MIN_TEXT_HEIGHT);
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const visibleLabel = useTypewriterText(label, `${id}:${label}`);

  useEffect(() => {
    if (!editing) return;

    window.setTimeout(() => editorRef.current?.focus(), 0);
  }, [editing]);

  useLayoutEffect(() => {
    if (!editing) return;

    const editor = editorRef.current;
    if (!editor) return;

    editor.style.height = 'auto';
    const nextHeight = Math.min(
      Math.max(Math.ceil(editor.scrollHeight), INLINE_EDITOR_MIN_TEXT_HEIGHT),
      INLINE_EDITOR_MAX_TEXT_HEIGHT,
    );
    editor.style.height = `${nextHeight}px`;
    setDraftTextHeight(nextHeight);
  }, [draftText, editing]);

  if (phase === 'notch-cue' || phase === 'fading') {
    return null;
  }

  const sx = spawnOrigin.x;
  const sy = spawnOrigin.y;
  const tx = target.x;
  const ty = target.y;
  const dx = tx - sx;
  const dy = ty - sy;
  const endAngleDeg = (Math.atan2(dy, dx) * 180) / Math.PI;
  const pathD = `M ${sx},${sy} L ${tx},${ty}`;
  const isTraveling = phase === 'traveling';
  const isHolding = phase === 'holding';
  const labelIsExpanded = labelHovered && collapsedLabelNeedsExpansion(label);
  const labelSize = editing
    ? inlineEditorSize(label)
    : {
        width: labelIsExpanded ? EXPANDED_LABEL_CONTENT_WIDTH + LABEL_HORIZONTAL_PADDING * 2 : COLLAPSED_LABEL_WIDTH,
        height: labelIsExpanded ? expandedLabelHeight(label) : collapsedLabelHeight(label),
      };
  const offset = labelOffset(target, labelSize, desktopSize);
  const cursorStyle: MotionPathStyle = isTraveling
    ? {
        left: 0,
        top: 0,
        width: 28,
        height: 28,
        offsetPath: `path("${pathD}")`,
        WebkitOffsetPath: `path("${pathD}")`,
        offsetRotate: `auto ${CURSOR_BASE_ROTATION_DEG}deg`,
        WebkitOffsetRotate: `auto ${CURSOR_BASE_ROTATION_DEG}deg`,
        animation: `spawnTravel-${id} ${TRAVEL_DURATION_MS}ms cubic-bezier(0.45, 0.05, 0.3, 1) both`,
      }
    : {
        left: target.x,
        top: target.y,
        width: 28,
        height: 28,
        transform: `translate(-50%, -50%) rotate(${endAngleDeg + CURSOR_BASE_ROTATION_DEG}deg)`,
      };

  const submitInlineFollowUp = () => {
    const text = draftText.trim();
    if (!text) {
      onCancelEditing();
      return;
    }

    onSubmitFollowUp(text);
    setDraftText('');
  };

  const handleEditorKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      onCancelEditing();
      return;
    }

    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      submitInlineFollowUp();
    }
  };

  return (
    <>
      <style>{`
        @keyframes spawnTravel-${id} {
          0%   { offset-distance: 0%; opacity: 0; }
          14%  { opacity: 1; }
          100% { offset-distance: 100%; opacity: 1; }
        }
        @keyframes spawnTerminalTail-${id} {
          0%, 50%, 100% { transform: rotate(0deg); }
          12.5%         { transform: rotate(-14deg); }
          37.5%         { transform: rotate(-7deg); }
          62.5%         { transform: rotate(14deg); }
          87.5%         { transform: rotate(7deg); }
        }
        @keyframes spawnWorkingPulse-${id} {
          0%, 100% { transform: scale(1); }
          50%      { transform: scale(1.08); }
        }
        @keyframes spawnHaloPulse-${id} {
          0%, 100% { transform: translate(-50%, -50%) scale(1); opacity: 0.6; }
          50%      { transform: translate(-50%, -50%) scale(1.15); opacity: 0.2; }
        }
      `}</style>

      {isHolding && (
        <div
          className="absolute pointer-events-none rounded-full"
          style={{
            left: target.x,
            top: target.y + HALO_VERTICAL_OFFSET,
            width: 40,
            height: 40,
            border: `1.5px solid ${color}`,
            transform: 'translate(-50%, -50%)',
            animation: `spawnHaloPulse-${id} 1.6s ease-in-out 700ms infinite`,
            zIndex: 29,
          }}
        />
      )}

      <button
        type="button"
        data-spawn-interactive="true"
        className="absolute z-30 cursor-default border-0 bg-transparent p-0"
        style={cursorStyle}
        onPointerDown={(event) => {
          event.stopPropagation();
          onSelect();
        }}
        aria-label={selected ? 'Selected Donkey agent' : 'Select Donkey agent'}
      >
        <div
          style={{
            transformOrigin: '50% 50%',
            animation: isHolding ? `spawnTerminalTail-${id} 700ms ease-in-out both` : 'none',
          }}
        >
          <div
            style={{
              transformOrigin: '50% 50%',
              animation: isHolding ? `spawnWorkingPulse-${id} 1.4s ease-in-out 700ms infinite` : 'none',
            }}
          >
            <DonkeyCursor color={color} />
          </div>
        </div>
      </button>

      {isHolding && (
        <div
          data-spawn-interactive="true"
          className="absolute text-white"
          style={{
            left: target.x + offset.x,
            top: target.y + offset.y,
            width: labelSize.width,
            minHeight: labelSize.height,
            transform: 'translate(-50%, -50%)',
            zIndex: 29,
          }}
          onPointerDown={(event) => event.stopPropagation()}
          onMouseEnter={() => setLabelHovered(true)}
          onMouseLeave={() => setLabelHovered(false)}
        >
          <div
            className="overflow-hidden"
            style={{
              borderRadius: 8,
              background: color,
              boxShadow: selected ? '0 0 0 1px rgba(255,255,255,0.28), 0 4px 14px rgba(0,0,0,0.24)' : 'none',
            }}
          >
            {editing ? (
              <div
                style={{
                  width: INLINE_EDITOR_CONTENT_WIDTH + INLINE_EDITOR_HORIZONTAL_PADDING * 2,
                  padding: `${INLINE_EDITOR_VERTICAL_PADDING}px ${INLINE_EDITOR_HORIZONTAL_PADDING}px`,
                }}
              >
                <div
                  className="overflow-hidden text-left font-medium text-white"
                  style={{
                    width: INLINE_EDITOR_CONTENT_WIDTH,
                    maxHeight: 42,
                    fontSize: LABEL_FONT_SIZE,
                    lineHeight: '14px',
                    display: '-webkit-box',
                    WebkitLineClamp: 3,
                    WebkitBoxOrient: 'vertical',
                  }}
                >
                  {label}
                </div>
                <div
                  className="mt-3 overflow-hidden"
                  style={{
                    width: INLINE_EDITOR_CONTENT_WIDTH,
                    height: INLINE_EDITOR_INPUT_HEIGHT,
                    padding: '8px 12px',
                    borderRadius: 7,
                    background: inputAccentColor(color),
                  }}
                >
                  <textarea
                    ref={editorRef}
                    rows={1}
                    value={draftText}
                    onChange={(event) => setDraftText(event.target.value)}
                    onKeyDown={handleEditorKeyDown}
                    className="block w-full resize-none overflow-hidden border-0 bg-transparent p-0 text-left font-medium outline-none"
                    style={{
                      height: draftTextHeight,
                      color: 'rgba(0,0,0,0.68)',
                      caretColor: 'rgba(0,0,0,0.72)',
                      fontSize: LABEL_FONT_SIZE,
                      lineHeight: '14px',
                      fontVariantLigatures: 'none',
                    }}
                    aria-label="Follow-up"
                  />
                </div>
              </div>
            ) : (
              <button
                type="button"
                className="block w-full border-0 bg-transparent text-left text-white"
                style={{
                  padding: `${LABEL_VERTICAL_PADDING}px ${LABEL_HORIZONTAL_PADDING}px`,
                  fontSize: LABEL_FONT_SIZE,
                  fontWeight: 500,
                  lineHeight: `${LABEL_LINE_HEIGHT}px`,
                }}
                onClick={onBeginEditing}
                onPointerDown={() => {
                  setDraftText('');
                  setDraftTextHeight(INLINE_EDITOR_MIN_TEXT_HEIGHT);
                }}
              >
                <span
                  className="block overflow-hidden"
                  style={{
                    maxWidth: labelIsExpanded ? EXPANDED_LABEL_CONTENT_WIDTH : COLLAPSED_LABEL_CONTENT_WIDTH,
                    display: labelIsExpanded ? 'block' : '-webkit-box',
                    WebkitLineClamp: labelIsExpanded ? 'unset' : 2,
                    WebkitBoxOrient: 'vertical',
                    whiteSpace: 'pre-wrap',
                    textOverflow: 'ellipsis',
                  }}
                >
                  {visibleLabel}
                </span>
              </button>
            )}
          </div>
        </div>
      )}
    </>
  );
}
