import os
import json
import time
from urllib.parse import quote

import requests
import streamlit as st
from dotenv import load_dotenv


load_dotenv()

st.set_page_config(
    page_title="Free-First LLM Cost Saver",
    page_icon="⚡",
    layout="wide",
)

STATE_FILE = "gateway_final_v3.json"
TODAY = time.strftime("%Y-%m-%d")


def load_persisted_telemetry():
    defaults = {
        "Cerebras (GPT-OSS 120B)": {"limit": "Free trial: 5 RPM / 30K TPM / 1M TPD", "daily_limit": 1_000_000, "daily_used": 0, "quota_date": TODAY, "remaining": "1,000,000", "session_used": 0, "latency": "0.0s", "status": "unconfigured"},
        "Cerebras (GLM 4.7)": {"limit": "Free trial: 5 RPM / 30K TPM / 1M TPD", "daily_limit": 1_000_000, "daily_used": 0, "quota_date": TODAY, "remaining": "1,000,000", "session_used": 0, "latency": "0.0s", "status": "unconfigured"},
        "Groq (Llama 3.3 70B)": {"limit": "Free: 30 RPM / 1K RPD / 100K TPD", "daily_limit": 100_000, "daily_used": 0, "quota_date": TODAY, "remaining": "100,000", "session_used": 0, "latency": "0.0s", "status": "unconfigured"},
        "Gemini 3.5 Flash (Google Free)": {"limit": "Free tier", "daily_limit": 1_000_000, "daily_used": 0, "quota_date": TODAY, "remaining": "1,000,000", "session_used": 0, "latency": "0.0s", "status": "unconfigured"},
        "OpenAI (GPT-4o Mini)": {"limit": "Paid", "daily_limit": None, "daily_used": 0, "quota_date": TODAY, "remaining": "Paid", "session_used": 0, "latency": "0.0s", "status": "unconfigured"},
        "Anthropic (Claude Haiku 4.5)": {"limit": "Paid", "daily_limit": None, "daily_used": 0, "quota_date": TODAY, "remaining": "Paid", "session_used": 0, "latency": "0.0s", "status": "unconfigured"},
    }
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
            return {
                key: normalize_quota({**value, **saved.get(key, {})})
                for key, value in defaults.items()
            }
        except Exception:
            return defaults
    return defaults


def normalize_quota(data):
    if data.get("quota_date") != TODAY:
        data["quota_date"] = TODAY
        data["daily_used"] = 0
    daily_limit = data.get("daily_limit")
    if daily_limit:
        data["remaining"] = f"{max(0, daily_limit - data.get('daily_used', 0)):,}"
    else:
        data["remaining"] = "Paid"
    return data


def save_persisted_telemetry(data):
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f)
    except Exception:
        pass


def require_session_defaults():
    st.session_state.setdefault("live_telemetry", load_persisted_telemetry())
    st.session_state.setdefault("routing_mode", "Auto Fallback Pipeline")
    st.session_state.setdefault("last_response", None)
    st.session_state.setdefault("last_errors", [])
    st.session_state.setdefault("last_pipeline_error", None)
    if (
        st.session_state.routing_mode == "Gemini 3.5 Flash (Google Free)"
        and not st.session_state.get("gemini_demoted_from_default")
    ):
        st.session_state.routing_mode = "Auto Fallback Pipeline"
        st.session_state.gemini_demoted_from_default = True


require_session_defaults()

st.markdown(
    """
    <style>
        .block-container { padding-top: 2rem; padding-bottom: 2rem; }
        .telemetry-card {
            border-radius: 8px;
            padding: 13px 16px;
            background-color: #1e222b;
            height: 340px;
            margin-bottom: 12px;
            display: flex;
            flex-direction: column;
            box-sizing: border-box;
            overflow: hidden;
        }
        .accent-connected { border-left: 5px solid #28a745; }
        .accent-error { border-left: 5px solid #dc3545; }
        .accent-unconfigured { border-left: 5px solid #6c757d; }
        .card-selected { border: 2px solid #eab308 !important; }
        .model-title { font-size: 0.95rem; font-weight: 700; color: #ffffff; margin-bottom: 1px; line-height: 1.18; }
        .provider-tag { font-size: 0.68rem; color: #8a92a6; text-transform: uppercase; margin-bottom: 6px; min-height: 15px; line-height: 1.18; }
        .metric-label { font-size: 0.68rem; color: #a0aec0; margin-top: 5px; line-height: 1.12; }
        .metric-value { font-size: 0.86rem; font-weight: 600; color: #f7fafc; line-height: 1.15; overflow-wrap: anywhere; }
        .metric-value.small { font-size: 0.74rem; color: #a0aec0; }
        .quota-value { color: #38bdf8; }
        div[data-testid="stButton"] > button[kind="secondary"] {
            background-color: #fff2a8 !important;
            border: 1px solid #f4cf45 !important;
            color: #2f2f2f !important;
            height: 46px !important;
            font-weight: 600 !important;
        }
        .st-key-submit_query_btn button {
            background-color: #7dd3fc !important;
            border: 1px solid #38bdf8 !important;
            color: #0f172a !important;
            height: 45px !important;
            width: 100% !important;
            font-weight: 700 !important;
            border-radius: 8px !important;
        }
        .st-key-clear_window_btn button {
            background-color: #ef4444 !important;
            border: 1px solid #dc2626 !important;
            color: white !important;
            height: 50px !important;
            width: 100% !important;
            font-weight: 700 !important;
            border-radius: 8px !important;
        }
        .st-key-submit-query-btn button,
        .st-key-main_actions div[data-testid="column"]:nth-child(1) button,
        .st-key-main-actions div[data-testid="column"]:nth-child(1) button,
        div[data-testid="stHorizontalBlock"]:has(.st-key-submit_query_btn) div[data-testid="column"]:nth-child(1) button {
            background-color: #7dd3fc !important;
            border: 1px solid #38bdf8 !important;
            color: #0f172a !important;
            height: 45px !important;
            min-height: 45px !important;
            width: 100% !important;
            font-weight: 700 !important;
            border-radius: 8px !important;
        }
        .st-key-clear-window-btn button,
        .st-key-main_actions div[data-testid="column"]:nth-child(2) button,
        .st-key-main-actions div[data-testid="column"]:nth-child(2) button,
        div[data-testid="stHorizontalBlock"]:has(.st-key-submit_query_btn) div[data-testid="column"]:nth-child(2) button {
            background-color: #ef4444 !important;
            border: 1px solid #dc2626 !important;
            color: white !important;
            height: 50px !important;
            min-height: 50px !important;
            width: 100% !important;
            font-weight: 700 !important;
            border-radius: 8px !important;
        }
    </style>
    """,
    unsafe_allow_html=True,
)


def clear_session_callback():
    st.session_state.user_input_query = ""
    st.session_state.last_response = None
    st.session_state.last_errors = []
    st.session_state.last_pipeline_error = None


def env_value(name):
    value = os.environ.get(name)
    return value.strip() if value else ""


def gemini_key():
    return env_value("GEMINI_API_KEY") or env_value("GOOGLE_API_KEY")


def cerebras_headers():
    return {
        "Authorization": f"Bearer {env_value('CEREBRAS_API_KEY')}",
        "Content-Type": "application/json",
    }


def build_targets(system_msg, user_msg):
    google_key = quote(gemini_key(), safe="")
    return [
        {
            "name": "Cerebras (GPT-OSS 120B)",
            "key": "CEREBRAS_API_KEY",
            "key_value": env_value("CEREBRAS_API_KEY"),
            "url": "https://api.cerebras.ai/v1/chat/completions",
            "headers": cerebras_headers(),
            "payload": {"model": "gpt-oss-120b", "temperature": 0.7, "max_completion_tokens": 2048, "messages": [{"role": "system", "content": system_msg}, {"role": "user", "content": user_msg}]},
            "format": "openai",
        },
        {
            "name": "Cerebras (GLM 4.7)",
            "key": "CEREBRAS_API_KEY",
            "key_value": env_value("CEREBRAS_API_KEY"),
            "url": "https://api.cerebras.ai/v1/chat/completions",
            "headers": cerebras_headers(),
            "payload": {"model": "zai-glm-4.7", "temperature": 0.7, "max_completion_tokens": 2048, "messages": [{"role": "system", "content": system_msg}, {"role": "user", "content": user_msg}]},
            "format": "openai",
        },
        {
            "name": "Groq (Llama 3.3 70B)",
            "key": "GROQ_API_KEY",
            "key_value": env_value("GROQ_API_KEY"),
            "url": "https://api.groq.com/openai/v1/chat/completions",
            "headers": {"Authorization": f"Bearer {env_value('GROQ_API_KEY')}", "Content-Type": "application/json"},
            "payload": {"model": "llama-3.3-70b-versatile", "temperature": 0.7, "messages": [{"role": "system", "content": system_msg}, {"role": "user", "content": user_msg}]},
            "format": "openai",
        },
        {
            "name": "Gemini 3.5 Flash (Google Free)",
            "key": "GEMINI_API_KEY or GOOGLE_API_KEY",
            "key_value": gemini_key(),
            "url": f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key={google_key}",
            "headers": {"Content-Type": "application/json"},
            "payload": {
                "systemInstruction": {"parts": [{"text": system_msg}]},
                "contents": [{"role": "user", "parts": [{"text": user_msg}]}],
                "generationConfig": {"temperature": 0.7, "candidateCount": 1},
            },
            "format": "gemini",
            "timeout": 18,
            "retries": 1,
        },
        {
            "name": "OpenAI (GPT-4o Mini)",
            "key": "OPENAI_API_KEY",
            "key_value": env_value("OPENAI_API_KEY"),
            "url": "https://api.openai.com/v1/chat/completions",
            "headers": {"Authorization": f"Bearer {env_value('OPENAI_API_KEY')}", "Content-Type": "application/json"},
            "payload": {"model": "gpt-4o-mini", "temperature": 0.7, "messages": [{"role": "system", "content": system_msg}, {"role": "user", "content": user_msg}]},
            "format": "openai",
        },
        {
            "name": "Anthropic (Claude Haiku 4.5)",
            "key": "ANTHROPIC_API_KEY",
            "key_value": env_value("ANTHROPIC_API_KEY"),
            "url": "https://api.anthropic.com/v1/messages",
            "headers": {"x-api-key": env_value("ANTHROPIC_API_KEY"), "anthropic-version": "2023-06-01", "Content-Type": "application/json"},
            "payload": {"model": "claude-haiku-4-5-20251001", "max_tokens": 1024, "system": system_msg, "messages": [{"role": "user", "content": user_msg}], "temperature": 0.7},
            "format": "anthropic",
        },
    ]


def parse_response(target, res_json):
    if target["format"] == "openai":
        content = res_json["choices"][0]["message"]["content"]
        tokens = res_json.get("usage", {}).get("total_tokens", 0)
    elif target["format"] == "anthropic":
        content = res_json["content"][0]["text"]
        usage = res_json.get("usage", {})
        tokens = usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
    elif target["format"] == "gemini":
        candidates = res_json.get("candidates") or []
        if not candidates:
            reason = res_json.get("promptFeedback") or res_json.get("error") or res_json
            raise ValueError(f"Gemini returned no candidates: {json.dumps(reason, indent=2)[:1200]}")
        finish_reason = candidates[0].get("finishReason")
        if finish_reason and finish_reason not in {"STOP", "MAX_TOKENS"}:
            raise ValueError(f"Gemini stopped with finishReason={finish_reason}: {json.dumps(candidates[0], indent=2)[:1200]}")
        content = res_json["candidates"][0]["content"]["parts"][0]["text"]
        usage = res_json.get("usageMetadata", {})
        tokens = usage.get("totalTokenCount") or usage.get("promptTokenCount", 0) + usage.get("candidatesTokenCount", 0)
    else:
        raise ValueError(f"Unknown response format: {target['format']}")
    return content, tokens


def record_error(target_name, detail):
    if target_name in st.session_state.live_telemetry:
        st.session_state.live_telemetry[target_name]["status"] = "error"
    st.session_state.last_errors.append({"name": target_name, "detail": detail})


def execute_live_telemetry_pipeline(system_msg, user_msg):
    sequence = build_targets(system_msg, user_msg)

    if st.session_state.routing_mode != "Auto Fallback Pipeline":
        sequence = [target for target in sequence if target["name"] == st.session_state.routing_mode]

    st.session_state.last_errors = []

    for target in sequence:
        if not target.get("key_value"):
            st.session_state.live_telemetry[target["name"]]["status"] = "unconfigured"
            st.session_state.last_errors.append(
                {"name": target["name"], "detail": f"Skipped: {target['key']} is not set or is blank in .env / environment."}
            )
            continue

        start_time = time.time()
        try:
            response = None
            request_errors = []
            attempts = target.get("retries", 0) + 1
            for attempt in range(attempts):
                try:
                    response = requests.post(
                        target["url"],
                        json=target["payload"],
                        headers=target["headers"],
                        timeout=target.get("timeout", 30),
                    )
                    if response.status_code not in {429, 500, 502, 503, 504}:
                        break
                    request_errors.append(f"Attempt {attempt + 1}: HTTP {response.status_code}\n{response.text[:1200]}")
                    if attempt + 1 < attempts:
                        time.sleep(0.8)
                except requests.RequestException as req_exc:
                    request_errors.append(f"Attempt {attempt + 1}: {req_exc}")
                    if attempt + 1 >= attempts:
                        raise
                    time.sleep(0.8)

            if response is None:
                record_error(target["name"], "\n\n".join(request_errors) or "No response returned.")
                continue

            latency = time.time() - start_time
            body = response.text[:3000]

            if response.status_code != 200:
                retry_detail = "\n\n".join(request_errors)
                detail = f"HTTP {response.status_code}\n{body}"
                if retry_detail:
                    detail = f"{retry_detail}\n\nFinal response:\n{detail}"
                record_error(target["name"], detail)
                continue

            res_json = response.json()
            try:
                content, tokens = parse_response(target, res_json)
            except (KeyError, IndexError, TypeError, ValueError) as parse_err:
                record_error(
                    target["name"],
                    f"200 OK but unexpected response shape ({parse_err}):\n{json.dumps(res_json, indent=2)[:3000]}",
                )
                continue

            st.session_state.live_telemetry[target["name"]]["status"] = "connected"
            st.session_state.live_telemetry[target["name"]]["latency"] = f"{latency:.3f}s"
            st.session_state.live_telemetry[target["name"]]["session_used"] += tokens
            st.session_state.live_telemetry[target["name"]]["daily_used"] = (
                st.session_state.live_telemetry[target["name"]].get("daily_used", 0) + tokens
            )
            normalize_quota(st.session_state.live_telemetry[target["name"]])
            save_persisted_telemetry(st.session_state.live_telemetry)
            return {"provider": target["name"], "text": content, "latency": f"{latency:.2f}s", "tokens": tokens}
        except Exception as exc:
            record_error(target["name"], str(exc))

    save_persisted_telemetry(st.session_state.live_telemetry)
    raise RuntimeError("All routing models failed or required keys are missing. See sidebar diagnostics for exact provider responses.")


with st.sidebar:
    st.header("🔑 API Infrastructure Status")
    keys_to_check = [
        ("Cerebras", env_value("CEREBRAS_API_KEY"), "CEREBRAS_API_KEY"),
        ("Groq", env_value("GROQ_API_KEY"), "GROQ_API_KEY"),
        ("Gemini", gemini_key(), "GEMINI_API_KEY or GOOGLE_API_KEY"),
        ("OpenAI", env_value("OPENAI_API_KEY"), "OPENAI_API_KEY"),
        ("Anthropic", env_value("ANTHROPIC_API_KEY"), "ANTHROPIC_API_KEY"),
    ]
    for label, key_value, env_key in keys_to_check:
        if key_value:
            st.success(f"🟢 {label} Key Detected")
        else:
            st.warning(f"🔴 {label} Key Missing ({env_key})")

    st.markdown("---")
    st.markdown(f"**Route Logic:** `{st.session_state.routing_mode}`")

    # Added by Piyush Sharma
    st.markdown(
        """
        <h4 style="color:#1E88E5; text-decoration: underline; margin-bottom:0;">
            An AI Solution by Piyush Sharma
        </h4>
        """,
        unsafe_allow_html=True
    )

    if st.session_state.last_errors:
        st.markdown("---")
        st.subheader("🩺 Last Request Diagnostics")
        for err in st.session_state.last_errors:
            with st.expander(f"❌ {err['name']}"):
                st.code(err["detail"], language="text")


st.title("⚡ Free-First LLM Cost Saver")
st.markdown("### 📊 Route free models first, then paid fallbacks")

STATUS_DISPLAY = {
    "connected": {"accent": "accent-connected", "label": "Connected", "color": "#28a745"},
    "error": {"accent": "accent-error", "label": "Not Connected", "color": "#dc3545"},
    "unconfigured": {"accent": "accent-unconfigured", "label": "Offline", "color": "#6c757d"},
}

cols = st.columns(6)
for idx, (provider, data) in enumerate(st.session_state.live_telemetry.items()):
    is_selected = st.session_state.routing_mode == provider
    display = STATUS_DISPLAY[data.get("status", "unconfigured")]
    card_style = f"telemetry-card {display['accent']}"
    if is_selected:
        card_style += " card-selected"

    with cols[idx]:
        model_title = provider.split("(", 1)[1].replace(")", "") if "(" in provider else provider
        provider_tag = provider.split("(", 1)[0].strip()
        normalize_quota(data)
        free_remaining = data.get("remaining", "Paid")
        quota_display = f"{free_remaining} tokens" if data.get("daily_limit") else "Paid plan"
        daily_used = data.get("daily_used", 0)
        st.markdown(
            f"""
            <div class="{card_style}">
                <div class="model-title">{model_title}</div>
                <div class="provider-tag">{provider_tag}</div>
                <div class="metric-label">Status</div>
                <div class="metric-value" style="color: {display['color']}; font-size:0.95rem;">{display['label']}</div>
                <div class="metric-label">Last Latency</div>
                <div class="metric-value">{data['latency']}</div>
                <div class="metric-label">Free Tokens Left Today</div>
                <div class="metric-value quota-value">{quota_display}</div>
                <div class="metric-label">Used Today</div>
                <div class="metric-value small">{daily_used:,} tokens</div>
                <div class="metric-label">Session Footprint</div>
                <div class="metric-value small">{data['session_used']:,} tokens</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

        btn_label = "🔒 Locked" if is_selected else "Select Engine"
        if st.button(btn_label, key=f"sel_{idx}", use_container_width=True, type="secondary"):
            st.session_state.routing_mode = "Auto Fallback Pipeline" if is_selected else provider
            st.rerun()

st.markdown("---")
st.subheader("💬 Ask Your Query")
user_prompt = st.text_area(
    "Input Prompt:",
    key="user_input_query",
    placeholder="Send a message to your speed-optimized model array...",
    height=110,
    label_visibility="collapsed",
)

with st.container(key="main_actions"):
    act_col1, act_col2, _ = st.columns([2, 2, 8])
    with act_col1:
        submit = st.button("Submit Query", key="submit_query_btn", type="primary", use_container_width=True)
    with act_col2:
        st.button("Clear Window", key="clear_window_btn", type="secondary", use_container_width=True, on_click=clear_session_callback)

if submit and user_prompt.strip():
    with st.spinner("Routing model request handshake..."):
        try:
            st.session_state.last_response = execute_live_telemetry_pipeline(
                system_msg="You are a precise, direct engineering assistant.",
                user_msg=user_prompt,
            )
            st.session_state.last_pipeline_error = None
        except Exception as exc:
            st.session_state.last_pipeline_error = str(exc)
    st.rerun()

if st.session_state.last_pipeline_error:
    st.error(f"💀 Gateway Pipeline Failure: {st.session_state.last_pipeline_error}")
    st.caption("See '🩺 Last Request Diagnostics' in the sidebar for the exact error from each provider.")

if st.session_state.last_response:
    res = st.session_state.last_response
    st.success(f"🟢 Handled Successfully by **{res['provider']}** in **{res['latency']}**")
    st.markdown("#### Response:")
    st.info(res["text"])
