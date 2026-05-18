import type { Metadata } from "next";

import NotchPrototypeApp from "@/app/prototype/_components/App";

export const runtime = "nodejs";

export const metadata: Metadata = {
  title: "Donkey Notch Prototype",
  description: "Interactive Donkey notch prototype.",
};

export default function Page() {
  return <NotchPrototypeApp />;
}
