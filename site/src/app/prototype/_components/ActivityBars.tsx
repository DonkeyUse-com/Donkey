type Props = {
  color?: string;
  height?: number;
};

const BAR_SCALES = [0.44, 0.82, 0.58] as const;

export function ActivityBars({ color = '#fff', height = 18 }: Props) {
  return (
    <div className="flex w-[18px] flex-shrink-0 items-center justify-center gap-[3px]" style={{ height }}>
      {BAR_SCALES.map((scale) => (
        <span
          key={scale}
          className="w-[3px] rounded-full"
          style={{ height: height * scale, background: color }}
        />
      ))}
    </div>
  );
}
