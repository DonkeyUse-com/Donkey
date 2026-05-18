import type { ReactNode } from 'react';

type Props = {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
  accent?: string;
};

export function ControlButton({ active, onClick, children, accent }: Props) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="px-3 py-2 text-left rounded-lg transition-all border text-sm flex items-start gap-2.5"
      style={{
        background: active ? '#1a1a1a' : '#fff',
        color: active ? '#fff' : '#1a1a1a',
        borderColor: active ? '#1a1a1a' : '#e5e3dc',
      }}
    >
      {accent && <div className="w-1 self-stretch rounded-full mt-0.5" style={{ background: accent }} />}
      <div className="flex-1">{children}</div>
    </button>
  );
}
