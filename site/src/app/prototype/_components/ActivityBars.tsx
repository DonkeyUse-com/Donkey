type Props = {
  color?: string;
};

export function ActivityBars({ color = '#fff' }: Props) {
  return (
    <>
      <style>{`
        @keyframes ab1 { 0%,100%{height:7px;opacity:1} 50%{height:3px;opacity:0.5} }
        @keyframes ab2 { 0%,100%{height:4px;opacity:0.6} 50%{height:9px;opacity:1} }
        @keyframes ab3 { 0%,100%{height:9px;opacity:1} 50%{height:5px;opacity:0.7} }
        .ab1 { animation: ab1 1.1s ease-in-out infinite; }
        .ab2 { animation: ab2 1.1s ease-in-out infinite; }
        .ab3 { animation: ab3 1.1s ease-in-out infinite; }
      `}</style>
      <div className="flex gap-[2px] items-center flex-shrink-0">
        <div className="w-[2px] rounded-sm ab1" style={{ background: color }} />
        <div className="w-[2px] rounded-sm ab2" style={{ background: color }} />
        <div className="w-[2px] rounded-sm ab3" style={{ background: color }} />
      </div>
    </>
  );
}
