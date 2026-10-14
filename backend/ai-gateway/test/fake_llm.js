/** 按顺序返回预设回复的假 LLM；最后一条会一直重复。回复可以是字符串、Error 或函数。 */
export const fakeLlm = (replies, calls = []) => ({
  model: 'fake', configured: true,
  async chat(messages) {
    calls.push(messages);
    const r = replies.length > 1 ? replies.shift() : replies[0];
    if (r instanceof Error) throw r;
    return typeof r === 'function' ? r(messages) : r;
  },
});
