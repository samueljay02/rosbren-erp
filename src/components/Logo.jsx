export default function Logo({ size = 40 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" aria-label="Rosbren logo" role="img">
      <circle cx="32" cy="32" r="31" fill="#E2D54B" />
      <circle cx="32" cy="32" r="20" fill="#3F8E7E" stroke="#1F5C52" strokeWidth="4" />
      <path d="M27 17c5-2 9 0 11 3s5 4 4 8-4 5-4 9-3 8-6 9c-1-4-2-7-4-9s-4-5-3-9 2-8 2-11z" fill="#A9D2C8" stroke="#1F5C52" strokeWidth="1.5" />
    </svg>
  );
}
