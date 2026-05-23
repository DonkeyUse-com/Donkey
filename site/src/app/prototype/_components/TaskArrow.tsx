type Props = {
  color: string;
  size?: number;
  className?: string;
};

export function TaskArrow({ color, size = 14, className }: Props) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 14 14"
      aria-hidden="true"
      className={`flex-shrink-0 ${className ?? ''}`}
    >
      <path d="M2.52 0.84 12.32 7 2.52 13.16 4.76 7 2.52 0.84Z" fill={color} />
    </svg>
  );
}
