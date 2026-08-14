const messagesEl = document.getElementById("messages");
const formEl = document.getElementById("chat-form");
const inputEl = document.getElementById("message-input");
const sendButtonEl = document.getElementById("send-button");
const userNameEl = document.getElementById("user-name");
const newConversationButtonEl = document.getElementById("new-conversation-button");

const CONVERSATION_STORAGE_KEY = "costAdvisorConversationId";

function addMessage(role, text) {
  const el = document.createElement("div");
  el.className = `message ${role}`;

  if (role === "assistant") {
    // Assistant replies are Markdown by design (the agent's instructions ask
    // for structured, formatted output). Render it properly rather than
    // showing literal ## and ** characters — but since this goes through
    // innerHTML, sanitize first. The agent's replies are ultimately built
    // from Azure resource data (subscription/service names, cost figures),
    // not arbitrary user input, but sanitizing costs nothing and removes
    // any doubt.
    el.innerHTML = DOMPurify.sanitize(marked.parse(text));
  } else {
    el.textContent = text;
  }

  messagesEl.appendChild(el);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  return el;
}

function getConversationId() {
  return sessionStorage.getItem(CONVERSATION_STORAGE_KEY);
}

function setConversationId(id) {
  if (id) {
    sessionStorage.setItem(CONVERSATION_STORAGE_KEY, id);
  }
}

function clearConversation() {
  sessionStorage.removeItem(CONVERSATION_STORAGE_KEY);
  messagesEl.innerHTML = "";
  addMessage("system", "Started a new conversation.");
}

newConversationButtonEl.addEventListener("click", clearConversation);

async function loadUserInfo() {
  try {
    const res = await fetch("/.auth/me");
    const data = await res.json();
    const principal = data && data.clientPrincipal;
    if (principal && principal.userDetails) {
      userNameEl.textContent = principal.userDetails;
    }
  } catch {
    // Not fatal — the chat still works without a display name.
  }
}

async function sendMessage(message) {
  const body = { message };
  const conversationId = getConversationId();
  if (conversationId) {
    body.conversation_id = conversationId;
  }

  const res = await fetch("/api/ChatWithAgent", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const data = await res.json();

  if (!res.ok) {
    const error = new Error(data.message || `Request failed (${res.status})`);
    error.status = data.status;
    throw error;
  }

  setConversationId(data.conversation_id);
  return data.reply;
}

formEl.addEventListener("submit", async (event) => {
  event.preventDefault();

  const message = inputEl.value.trim();
  if (!message) {
    return;
  }

  addMessage("user", message);
  inputEl.value = "";
  inputEl.disabled = true;
  sendButtonEl.disabled = true;

  const thinkingEl = addMessage("system", "Thinking...");

  try {
    const reply = await sendMessage(message);
    thinkingEl.remove();
    addMessage("assistant", reply);
  } catch (err) {
    thinkingEl.remove();
    if (err.status === "rate_limited") {
      // The backend's message is already clean and specific — showing it
      // directly, rather than wrapping it in "Something went wrong", since
      // this isn't an unexpected failure, it's a known, explained limit.
      addMessage("system", err.message);
    } else {
      addMessage("system", `Something went wrong: ${err.message}`);
    }
  } finally {
    inputEl.disabled = false;
    sendButtonEl.disabled = false;
    inputEl.focus();
  }
});

loadUserInfo();
