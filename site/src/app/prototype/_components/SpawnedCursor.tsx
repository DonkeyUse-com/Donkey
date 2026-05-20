import { DonkeyCursor } from '@/app/prototype/_components/DonkeyCursor';
import type { Point, Spawn } from '@/app/prototype/_components/types';

type Props = {
  spawn: Spawn;
  spawnOrigin: Point;
};

export function SpawnedCursor({ spawn, spawnOrigin }: Props) {
  const { id, color, label, target, phase } = spawn;

  const sx = spawnOrigin.x;
  const sy = spawnOrigin.y;
  const tx = target.x;
  const ty = target.y;
  const mx = (sx + tx) / 2;
  const my = (sy + ty) / 2;
  const dx = tx - sx;
  const dy = ty - sy;
  const len = Math.hypot(dx, dy) || 1;
  const px = -dy / len;
  const py = dx / len;
  const curveAmount = Math.min(80, len * 0.35) * (spawn.curveSide || 1);
  const cx = mx + px * curveAmount;
  const cy = my + py * curveAmount;
  const pathD = `M ${sx},${sy} Q ${cx},${cy} ${tx},${ty}`;

  const endAngleDeg = (Math.atan2(ty - cy, tx - cx) * 180) / Math.PI;

  const isEmerge = phase === 'emerge';
  const isTravel = phase === 'travel';
  const isShakeL = phase === 'shake-left';
  const isShakeR = phase === 'shake-right';
  const isWorking = phase === 'working';
  const useOffsetPath = isEmerge || isTravel;
  const cursorBaseRotation = 50;
  const labelLength = Math.max(Array.from(label).length, 1);
  const labelTypingDurationMs = Math.min(1300, Math.max(280, labelLength * 38));
  const labelWidth = `${labelLength + 1}ch`;

  return (
    <>
      <style>{`
        @keyframes emerge-${id} {
          0%   { offset-distance: 0%; opacity: 0; }
          40%  { opacity: 1; }
          100% { offset-distance: 0%; opacity: 1; }
        }
        @keyframes emergeScale-${id} {
          0%   { transform: rotate(${cursorBaseRotation}deg) scale(0.2); }
          50%  { transform: rotate(${cursorBaseRotation}deg) scale(1.2); }
          100% { transform: rotate(${cursorBaseRotation}deg) scale(1); }
        }
        @keyframes travel-${id} {
          0%   { offset-distance: 0%; }
          100% { offset-distance: 100%; }
        }
        @keyframes shakeL-${id} {
          0%, 100% { transform: rotate(0deg); }
          25%      { transform: rotate(-14deg); }
          75%      { transform: rotate(-7deg); }
        }
        @keyframes shakeR-${id} {
          0%, 100% { transform: rotate(0deg); }
          25%      { transform: rotate(14deg); }
          75%      { transform: rotate(7deg); }
        }
        @keyframes working-${id} {
          0%, 100% { transform: scale(1); }
          50%      { transform: scale(1.08); }
        }
        @keyframes haloPulse-${id} {
          0%, 100% { transform: scale(1); opacity: 0.6; }
          50%      { transform: scale(1.15); opacity: 0.2; }
        }
      `}</style>

      {isWorking && (
        <div
          className="absolute pointer-events-none"
          style={{
            left: target.x - 18,
            top: target.y - 18,
            width: 36,
            height: 36,
            borderRadius: '50%',
            border: `1.5px solid ${color}`,
            animation: `haloPulse-${id} 1.6s ease-in-out infinite`,
            zIndex: 29,
          }}
        />
      )}

      <div
        className="absolute pointer-events-none"
        style={{
          left: useOffsetPath ? 0 : target.x,
          top: useOffsetPath ? 0 : target.y,
          ...(useOffsetPath && {
            offsetPath: `path("${pathD}")`,
            WebkitOffsetPath: `path("${pathD}")`,
            offsetRotate: `auto ${cursorBaseRotation}deg`,
            WebkitOffsetRotate: `auto ${cursorBaseRotation}deg`,
            animation: isEmerge
              ? `emerge-${id} 0.5s cubic-bezier(0.32, 1.4, 0.5, 1) forwards`
              : `travel-${id} 0.9s cubic-bezier(0.45, 0.05, 0.3, 1) forwards`,
          }),
          zIndex: 30,
        }}
      >
        <div
          style={{
            transform: useOffsetPath ? 'none' : `rotate(${endAngleDeg + cursorBaseRotation}deg)`,
            transformOrigin: '0 0',
          }}
        >
          <div
            style={{
              transformOrigin: '0 0',
              animation: isEmerge
                ? `emergeScale-${id} 0.5s cubic-bezier(0.32, 1.4, 0.5, 1) forwards`
                : isShakeL
                ? `shakeL-${id} 0.35s ease-in-out`
                : isShakeR
                ? `shakeR-${id} 0.35s ease-in-out`
                : isWorking
                ? `working-${id} 1.4s ease-in-out infinite`
                : 'none',
            }}
          >
            <DonkeyCursor color={color} />
          </div>
        </div>
      </div>

      {(isShakeL || isShakeR || isWorking) && label && (
        (() => {
          const rad = (endAngleDeg * Math.PI) / 180;
          const dirX = Math.cos(rad);
          const dirY = Math.sin(rad);
          const offsetDist = 34;
          const anchorX = target.x - dirX * offsetDist;
          const anchorY = target.y - dirY * offsetDist;

          return (
            <div
              className="absolute inline-flex items-center whitespace-nowrap text-[10px] font-medium text-white px-2 py-0.5 rounded-md pointer-events-none animate-fadein-label"
              style={{
                background: color,
                left: anchorX,
                top: anchorY,
                transform: `translate(${(-50 - dirX * 50)}%, ${(-50 - dirY * 50)}%)`,
                boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
                zIndex: 29,
              }}
            >
              <span
                className="inline-block overflow-hidden whitespace-nowrap"
                style={{
                  maxWidth: labelWidth,
                  animation: `typeLabel-${id} ${labelTypingDurationMs}ms steps(${labelLength}, end) both`,
                }}
              >
                {label}
              </span>
              <span
                aria-hidden="true"
                className="ml-px inline-block h-[10px] w-px bg-white"
                style={{
                  animation: [
                    `labelCaretBlink-${id} 650ms steps(1, end) infinite`,
                    `labelCaretHide-${id} 1ms linear ${labelTypingDurationMs + 700}ms forwards`,
                  ].join(', '),
                }}
              />
            </div>
          );
        })()
      )}
      <style>{`
        @keyframes typeLabel-${id} {
          from { max-width: 0; }
          to   { max-width: ${labelWidth}; }
        }
        @keyframes labelCaretBlink-${id} {
          0%, 45% { opacity: 1; }
          46%, 100% { opacity: 0; }
        }
        @keyframes labelCaretHide-${id} {
          to { opacity: 0; }
        }
        @keyframes fadeinLabel-${id} {
          from { opacity: 0; }
          to   { opacity: 1; }
        }
        .animate-fadein-label { animation: fadeinLabel-${id} 0.2s ease-out both; }
      `}</style>
    </>
  );
}
