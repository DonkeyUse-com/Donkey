type Props = {
  color: string;
  size?: number;
};

export function DonkeyCursor({ color, size = 28 }: Props) {
  // The SVG's natural tip is at (~83, 5) in its 100x100 viewBox space (upper-right).
  // We position the SVG so that tip lands at the container's (0,0). That way, when
  // this element is placed on an offset-path or rotated, the TIP is the anchor.
  const tipX = 83 * (size / 100);
  const tipY = 5 * (size / 100);

  return (
    <div className="relative" style={{ width: 0, height: 0 }}>
      <svg
        viewBox="-5 -10 110 135"
        width={size}
        height={size}
        style={{
          position: 'absolute',
          left: -tipX,
          top: -tipY,
          filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.4))',
          overflow: 'visible',
        }}
      >
        <path
          d="m83.086 5.6406-72.633 29.043c-7.6016 3.0391-7.1445 13.949 0.67969 16.344l24.562 7.5195c2.7539 0.84375 4.9102 3 5.7539 5.7539l7.5195 24.562c2.3984 7.8281 13.305 8.2812 16.344 0.67969l29.043-72.633c2.832-7.0781-4.1953-14.102-11.273-11.273z"
          fill={color}
          stroke="white"
          strokeWidth="6"
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
}
