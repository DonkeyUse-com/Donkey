import { Smile, Moon, Plus, Sparkles, Check, Play } from 'lucide-react';
import type { CSSProperties } from 'react';

import { ActivityBars } from '@/app/prototype/_components/ActivityBars';
import { AGENTS, ALL_AGENT_IDS } from '@/app/prototype/_components/agents';
import type { AgentId, NotchState, SetHovering } from '@/app/prototype/_components/types';

type Props = {
  state: NotchState;
  activeAgentId: AgentId;
  hovering: boolean;
  setHovering: SetHovering;
  runningIds: AgentId[];
};

type RingStyle = CSSProperties & {
  '--ring'?: string;
};

export function Notch({ state, activeAgentId, hovering, setHovering, runningIds }: Props) {
  const activeAgent = AGENTS[activeAgentId];
  const isExpanded = hovering || state === 'expanded-pinned';

  const isComplete = state === 'complete';
  const isAttention = state === 'needs-input';
  const isMulti = state === 'running-multi';
  const isHero = isComplete || isAttention;

  let widthStyle: CSSProperties;
  if (isExpanded) widthStyle = { width: '440px' };
  else if (isHero) widthStyle = { width: '360px' };
  else if (isMulti) widthStyle = { width: '220px' };
  else if (state === 'running-single') widthStyle = { width: 'fit-content', minWidth: '200px', maxWidth: '460px' };
  else widthStyle = { width: '200px' };

  const ringColor = isComplete
    ? 'rgba(29,158,117,0.55)'
    : isAttention
    ? 'rgba(212,83,126,0.65)'
    : 'transparent';

  const ActiveIcon = activeAgent.Icon;
  const notchBodyStyle: RingStyle = {
    width: '100%',
    borderRadius: isExpanded ? '0 0 22px 22px' : isHero ? '0 0 22px 22px' : '0 0 14px 14px',
    boxShadow: !isExpanded && ringColor !== 'transparent' ? `0 0 0 1.5px ${ringColor}` : 'none',
    transition: 'border-radius 0.4s cubic-bezier(0.32, 0.72, 0, 1), box-shadow 0.3s ease',
    '--ring': ringColor,
  };

  return (
    <div
      className="absolute top-0 left-1/2 -translate-x-1/2 z-20"
      style={{
        ...widthStyle,
        transition: 'width 0.4s cubic-bezier(0.32, 0.72, 0, 1), min-width 0.4s cubic-bezier(0.32, 0.72, 0, 1), max-width 0.4s cubic-bezier(0.32, 0.72, 0, 1)',
      }}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      <style>{`
        @keyframes pulseRing {
          0%,100% { box-shadow: 0 0 0 1.5px var(--ring), 0 0 0 0 rgba(212,83,126,0); }
          50% { box-shadow: 0 0 0 1.5px var(--ring), 0 0 0 6px rgba(212,83,126,0.15); }
        }
        @keyframes fadeinUp {
          from { opacity: 0; transform: translateY(-4px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .pulse-attention { animation: pulseRing 1.6s ease-in-out infinite; }
        .fadein-up { animation: fadeinUp 0.3s cubic-bezier(0.32, 0.72, 0, 1) both; }
      `}</style>
      <div
        className={`bg-black mx-auto text-white overflow-hidden ${isAttention && !isExpanded ? 'pulse-attention' : ''}`}
        style={notchBodyStyle}
      >
        {!isExpanded && (state === 'idle' || state === 'running-single') && (
          <div className="flex items-center justify-center gap-2 pl-3.5 pr-4 py-1.5">
            <div
              className="w-3.5 h-3.5 rounded-full flex items-center justify-center flex-shrink-0"
              style={{ background: state === 'idle' ? '#444' : activeAgent.color }}
            >
              {state === 'idle' ? <Moon size={8} color="#fff" /> : <ActiveIcon size={8} color="#fff" />}
            </div>
            <span className="text-[10px] font-medium tracking-tight whitespace-nowrap text-white/95">
              {state === 'idle'
                ? 'Donkey · resting'
                : `${activeAgent.name} · ${activeAgent.subtitle.toLowerCase()}`}
            </span>
            {state === 'running-single' && <ActivityBars color={activeAgent.color} />}
          </div>
        )}

        {!isExpanded && isMulti && (
          <div className="flex items-center justify-center gap-2 px-3 py-1.5">
            <div className="flex items-center">
              {runningIds.slice(0, 4).map((id, i) => (
                <div
                  key={id}
                  className="w-3 h-3 rounded-full"
                  style={{
                    background: AGENTS[id].color,
                    border: '1.5px solid #000',
                    marginLeft: i === 0 ? 0 : '-4px',
                    zIndex: 10 - i,
                  }}
                />
              ))}
            </div>
            <span className="text-[10px] font-medium text-white/95 whitespace-nowrap">
              {runningIds.length} agents working
            </span>
            <ActivityBars color="rgba(255,255,255,0.85)" />
          </div>
        )}

        {!isExpanded && isComplete && (
          <div className="flex items-center gap-2.5 px-4 pt-1.5 pb-2.5 fadein-up">
            <div className="relative flex-shrink-0">
              <div className="w-7 h-7 rounded-md flex items-center justify-center" style={{ background: activeAgent.color }}>
                <ActiveIcon size={14} color="#fff" />
              </div>
              <div className="absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full bg-white flex items-center justify-center">
                <Check size={8} color={activeAgent.color} strokeWidth={3} />
              </div>
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-1.5">
                <span className="text-[11px] font-medium">{activeAgent.name} finished</span>
                <span className="text-[9px] text-white/50">· 1m 42s</span>
              </div>
              <div className="text-[10px] text-white/65 truncate">{activeAgent.subtitle}</div>
            </div>
            <button
              type="button"
              className="text-[10px] font-medium px-2 py-1 rounded"
              style={{ background: `${activeAgent.color}66`, color: '#fff' }}
            >
              View
            </button>
          </div>
        )}

        {!isExpanded && isAttention && (
          <div className="flex items-center gap-2.5 px-4 pt-1.5 pb-2.5 fadein-up">
            <div className="relative flex-shrink-0">
              <div className="w-7 h-7 rounded-md flex items-center justify-center" style={{ background: activeAgent.color }}>
                <ActiveIcon size={14} color="#fff" />
              </div>
              <div className="absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full bg-white flex items-center justify-center">
                <span style={{ fontSize: '9px', color: activeAgent.color, fontWeight: 700, lineHeight: 1 }}>!</span>
              </div>
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-1.5">
                <span className="text-[11px] font-medium">{activeAgent.name} needs you</span>
                <span className="text-[9px] text-white/50">· paused</span>
              </div>
              <div className="text-[10px] text-white/65 truncate">Pick a source for the search</div>
            </div>
            <button
              type="button"
              className="text-[10px] font-medium px-2 py-1 rounded"
              style={{ background: `${activeAgent.color}80`, color: '#fff' }}
            >
              Answer
            </button>
          </div>
        )}

        {isExpanded && (
          <div className="fadein-up">
            <div className="px-3.5 pt-2 pb-2 flex items-center gap-2 border-b border-white/10">
              <div className="w-3.5 h-3.5 rounded-full flex items-center justify-center" style={{ background: '#1D9E75' }}>
                <Smile size={8} color="#fff" />
              </div>
              <span className="text-[11px] font-medium">Donkey</span>
              <span className="text-[10px] text-white/45 ml-1">{runningIds.length} of 5 running</span>
              <div className="ml-auto flex items-center gap-1 text-[10px] text-white/45 hover:text-white/80 cursor-pointer">
                <Plus size={11} />
                <span>new task</span>
              </div>
            </div>

            <div className="p-2 flex flex-col gap-1">
              {ALL_AGENT_IDS.map((id) => {
                const a = AGENTS[id];
                const IconC = a.Icon;
                const isRunning = runningIds.includes(id);
                const isActiveStateAgent = activeAgentId === id && (state === 'complete' || state === 'needs-input');
                let statusLabel = isRunning ? 'running' : 'idle';
                let statusColor = isRunning ? a.color : 'rgba(255,255,255,0.4)';
                if (isActiveStateAgent && state === 'complete') statusLabel = 'done';
                if (isActiveStateAgent && state === 'needs-input') {
                  statusLabel = 'needs you';
                  statusColor = a.color;
                }

                return (
                  <div
                    key={id}
                    className="flex items-center gap-2.5 px-2 py-1.5 rounded-md hover:bg-white/5 cursor-pointer"
                    style={isRunning ? { background: `${a.color}1A`, borderLeft: `2px solid ${a.color}` } : {}}
                  >
                    <div className="w-5 h-5 rounded flex items-center justify-center flex-shrink-0" style={{ background: a.color }}>
                      <IconC size={11} color="#fff" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1.5">
                        <span className="text-[10px] font-medium">{a.name}</span>
                        <span
                          className="text-[9px] px-1 py-px rounded"
                          style={{
                            background: `${statusColor}30`,
                            color: statusColor === 'rgba(255,255,255,0.4)' ? 'rgba(255,255,255,0.5)' : statusColor,
                          }}
                        >
                          {statusLabel}
                        </span>
                      </div>
                      <div className="text-[9px] text-white/50 truncate">{isRunning ? a.subtitle : 'No active task'}</div>
                    </div>
                    {isRunning ? (
                      <ActivityBars color={a.color} />
                    ) : (
                      <Play size={11} color="rgba(255,255,255,0.4)" fill="rgba(255,255,255,0.4)" />
                    )}
                  </div>
                );
              })}
            </div>

            <div className="mx-2 mb-2 px-2.5 py-2 bg-white/[0.06] rounded-md flex items-center gap-2">
              <Sparkles size={11} color="rgba(255,255,255,0.5)" />
              <span className="text-[10px] text-white/40 flex-1">Tell donkey what to do…</span>
              <span className="text-[9px] text-white/30 px-1.5 py-px border border-white/15 rounded font-mono">⌘ K</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
