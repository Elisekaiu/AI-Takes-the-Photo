/**
 * 相机专属的轻量上下文缓存。这里只留文字，不保存 JPEG、base64 或模型原始请求。
 * 每次 Responses API 调用仍然是无状态的：不使用主聊天线程，也不累加图片历史。
 */
export const CAMERA_CONTEXT_LIMITS = Object.freeze({
  sessionMs: 12 * 60_000,
  checkpointMs: 2 * 60 * 60_000,
  rotateEveryFrames: 5,
  maxVisionFrames: 24,
  maxTextTurns: 20,
  recentLines: 6,
  noteLines: 5,
  maxMainIntroChars: 600,
  maxContextChars: 1_550,
  maxActiveSessions: 6,
});

export const shortText = (value, max = 180) => String(value ?? '')
  .replace(/[\u0000-\u001f\u007f]/g, ' ')
  .replace(/\s+/g, ' ')
  .trim().slice(0, max);

const isUUID = value => typeof value === 'string' &&
  /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value);
const clampCount = (value, max) => Number.isFinite(value)
  ? Math.max(0, Math.min(max, Math.trunc(value))) : 0;

export function makeCameraCheckpoint(session, { photosSaved = 0, now = Date.now() } = {}) {
  if (!session || !isUUID(session.id)) return null;
  const frames = clampCount(session.framesReviewed, 40);
  const photos = clampCount(photosSaved, 40);
  const conversations = clampCount(session.textTurns, 60);
  if (!frames && !photos && !conversations) return null;
  const goal = shortText(session.mainIntro, 80);
  const lastUser = shortText(session.lastUser, 85);
  const lastAdvice = shortText(session.lastAdvice, 105);
  const summary = [
    '刚刚一起打开相机，看了看生活里的小片刻。',
    `视觉取样分析 ${frames} 次，手机实际保存 ${photos} 张照片，相机小窗交流 ${conversations} 轮。`,
    goal && `此前聊天提到：${goal}。`,
    lastUser && `最后聊到：${lastUser}。`,
    lastAdvice && `AI 最近说：${lastAdvice}。`,
    '这是文字接续；没发送给主聊天的照片，不代表主聊天已经看过。',
  ].filter(Boolean).join(' ');
  return {
    id: session.id,
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + CAMERA_CONTEXT_LIMITS.checkpointMs).toISOString(),
    framesReviewed: frames,
    photosSaved: photos,
    textTurns: conversations,
    summary: shortText(summary, 430),
  };
}

/**
 * 对接任意主 Agent 的一次性短期接续收件箱。只有模型请求成功后才 acknowledge。
 * 不主动发送用户消息，不强制长期保存，也不读取用户历史。
 */
export class OneShotCameraInbox {
  constructor({ now = Date.now, maxItems = 2 } = {}) {
    this.now = now;
    this.maxItems = Math.max(1, Math.min(3, maxItems));
    this.pending = [];
  }
  offer(note) {
    if (!note || !isUUID(note.id) || typeof note.summary !== 'string') return false;
    this.prune();
    const at = Date.parse(note.expiresAt || '');
    if (!Number.isFinite(at) || at <= this.now()) return false;
    this.pending = this.pending.filter(item => item.id !== note.id);
    this.pending.push({ id: note.id, expiresAt: note.expiresAt, summary: shortText(note.summary, 430) });
    this.pending = this.pending.slice(-this.maxItems);
    return true;
  }
  prune() {
    const now = this.now();
    this.pending = this.pending.filter(item => Date.parse(item.expiresAt) > now);
  }
  peek() {
    this.prune();
    if (!this.pending.length) return null;
    return {
      ids: this.pending.map(item => item.id),
      text: '[最近一次相机陪伴｜短期文字接续，不代表持续看见实时画面]\n' +
        this.pending.map(item => item.summary).join('\n') +
        '\n[/最近一次相机陪伴]\n',
    };
  }
  acknowledge(receipt) {
    const ids = new Set(receipt?.ids || []);
    this.pending = this.pending.filter(item => !ids.has(item.id));
  }
}

/** 最多五帧一窗口；主线程只有一句摘要可以通过 end() 带走。 */
export class CameraContextSessions {
  constructor({ now = Date.now } = {}) {
    this.now = now;
    this.sessions = new Map();
    this.closed = new Map();
  }
  reap() {
    const now = this.now();
    for (const [id, session] of this.sessions) {
      if (now - session.createdAt > CAMERA_CONTEXT_LIMITS.sessionMs) {
        this.sessions.delete(id);
        this.closed.set(id, now);
      }
    }
    for (const [id, closedAt] of this.closed) {
      if (now - closedAt > CAMERA_CONTEXT_LIMITS.checkpointMs) this.closed.delete(id);
    }
  }
  start(sessionId, { mainContext = '' } = {}) {
    this.reap();
    if (!isUUID(sessionId)) throw new Error('invalid_session');
    const id = sessionId.toLowerCase();
    if (this.closed.has(id)) throw new Error('session_closed');
    let session = this.sessions.get(id);
    if (!session) {
      if (this.sessions.size >= CAMERA_CONTEXT_LIMITS.maxActiveSessions) throw new Error('too_many_sessions');
      session = {
        id, createdAt: this.now(), mainIntro: '', framesReviewed: 0,
        textTurns: 0, captureDecisions: 0, notes: [],
        visualWindow: 0, framesInWindow: 0,
        lastAdvice: '', lastUser: '', lastReply: '',
      };
      this.sessions.set(id, session);
    }
    // 可选、明确提供的简短聊天背景，只在首次启动时读取一次。
    if (!session.mainIntro) session.mainIntro = shortText(mainContext, CAMERA_CONTEXT_LIMITS.maxMainIntroChars);
    return session;
  }
  context(session, input) {
    const lines = [];
    if (session.mainIntro) lines.push(`打开相机前的简短聊天背景：${session.mainIntro}`);
    if (session.lastAdvice) lines.push(`上一轮视觉观察：${shortText(session.lastAdvice, 100)}`);
    const notes = session.notes.slice(-CAMERA_CONTEXT_LIMITS.noteLines);
    if (notes.length) lines.push('本相机会话里最近几句：' + notes.join(' / '));
    // 客户端传来的近期聊天最多六行，均为短文字，绝不包含历史图片。
    for (const entry of (input.recent || []).slice(-CAMERA_CONTEXT_LIMITS.recentLines)) {
      const label = entry.role === 'user' ? '用户' : '伙伴';
      const text = shortText(entry.text, 180);
      if (text) lines.push(`${label}：${text}`);
    }
    return shortText(lines.join('\n'), CAMERA_CONTEXT_LIMITS.maxContextChars);
  }
  record(session, input, decision) {
    if (!session || !this.sessions.has(session.id)) return;
    if (input.imageBase64) {
      session.framesReviewed += 1;
      session.framesInWindow += 1;
      if (session.framesInWindow >= CAMERA_CONTEXT_LIMITS.rotateEveryFrames) {
        session.visualWindow += 1;
        session.framesInWindow = 0;
        session.notes = session.notes.slice(-1); // 清掉较早的视觉话语
      }
    }
    if (input.message?.trim()) {
      session.textTurns += 1;
      session.lastUser = shortText(input.message, 100);
      session.notes.push('用户：' + session.lastUser);
    }
    session.lastAdvice = shortText(decision.say, 110);
    session.lastReply = session.lastAdvice;
    session.notes.push('AI：' + shortText(decision.say, 100));
    session.notes = session.notes.slice(-CAMERA_CONTEXT_LIMITS.noteLines);
    if (decision.action === 'CAPTURE') session.captureDecisions += 1; // 决定 ≠ 实际照片
  }
  end(sessionId, { photosSaved = 0 } = {}) {
    this.reap();
    if (!isUUID(sessionId)) throw new Error('invalid_session');
    const id = sessionId.toLowerCase();
    if (this.closed.has(id)) return null;
    this.closed.set(id, this.now());
    const session = this.sessions.get(id);
    this.sessions.delete(id);
    if (!session) return null;
    return makeCameraCheckpoint(session, { photosSaved, now: this.now() });
  }
  has(sessionId) { return this.sessions.has(String(sessionId).toLowerCase()); }
}
