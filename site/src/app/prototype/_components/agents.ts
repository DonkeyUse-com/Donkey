import { Code, Globe, Search, Mail, Calendar } from 'lucide-react';

import type { Agent, AgentId } from '@/app/prototype/_components/types';

export const AGENTS: Record<AgentId, Agent> = {
  coder: { id: 'coder', name: 'Coder', color: '#1D9E75', Icon: Code, subtitle: 'Ranking models on SWE-bench' },
  browser: { id: 'browser', name: 'Browser', color: '#EF9F27', Icon: Globe, subtitle: 'Pulling pricing from 3 sites' },
  researcher: { id: 'researcher', name: 'Researcher', color: '#D4537E', Icon: Search, subtitle: 'Reading 12 ArXiv papers' },
  inbox: { id: 'inbox', name: 'Inbox', color: '#378ADD', Icon: Mail, subtitle: 'Drafting reply to recruiter' },
  scheduler: { id: 'scheduler', name: 'Scheduler', color: '#7F77DD', Icon: Calendar, subtitle: 'Finding slots across KST/PT' },
};

export const ALL_AGENT_IDS = ['coder', 'browser', 'researcher', 'inbox', 'scheduler'] satisfies AgentId[];

export const SPAWN_COLORS = ['#1D9E75', '#EF9F27', '#D4537E', '#378ADD', '#7F77DD', '#E15A47', '#3DB0B5', '#A856C9'];
