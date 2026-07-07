# Free-First LLM Cost Saver

A Streamlit-based LLM routing dashboard that helps reduce paid-token usage by trying free or free-trial LLM providers first, then falling back to paid providers only when needed.

This is useful for AI research workflows, RAG systems, document analysis, validation pipelines, multi-agent workflows, and any project where repeated LLM calls can quickly increase token usage and billing.

## What It Does

- Routes prompts through free/free-trial models first.
- Keeps paid models available as fallback.
- Lets the user manually select any model at any time.
- Tracks latency, session tokens, daily usage, and estimated free tokens left.
- Shows provider status for configured API keys.
- Captures detailed provider errors in the sidebar diagnostics.

## Default Routing Order

1. Cerebras GPT-OSS 120B
2. Cerebras GLM 4.7
3. Groq Llama 3.3 70B
4. Gemini 3.5 Flash
5. OpenAI GPT-4o Mini
6. Anthropic Claude Haiku 4.5

Gemini is intentionally placed after the faster free/free-trial providers because it may be less reliable in some environments.

## Files

- `app.py` - main Streamlit app.
- `gateway_final_v3.json` - local telemetry state file created at runtime.
- `linkedin_article_free_first_llms.md` - short LinkedIn article draft.
- `free_first_llm_linkedin_cover.png` - LinkedIn cover image.
- 'img2` - routing concept diagram.
- `img1` - token-cost concept diagram.

## Setup

Install dependencies:

```bash
pip install streamlit requests python-dotenv
```

Create a `.env` file in the same directory where you run the app.

```env
CEREBRAS_API_KEY=your_cerebras_key_here
GROQ_API_KEY=your_groq_key_here
GEMINI_API_KEY=your_google_ai_studio_key_here
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here
```

You can also use `GOOGLE_API_KEY` instead of `GEMINI_API_KEY`.

Only the providers you want to use need keys. Missing keys are skipped automatically.

## Run

```bash
streamlit run app.py
```

If you are running from this output folder:

```bash
streamlit run outputs/app.py
```

## How Routing Works

By default, the app runs in auto-pipeline mode.

When a prompt is submitted:

1. The gateway checks the first configured model.
2. If the model succeeds, the response is returned.
3. If the model fails, times out, is rate-limited, or has no key, the gateway records the error and tries the next model.
4. Paid models are reached only after the free/free-trial routes fail or are unavailable.

You can also select a specific model from its card. This is useful when testing quality, latency, provider behavior, or intentionally using a paid model for a high-value task.

## Telemetry

Each model card shows:

- Connection status
- Last latency
- Estimated free tokens left today
- Used tokens today
- Session footprint

Daily token counters are local estimates based on calls made through this dashboard. They do not include usage from other apps or provider dashboards.

## Diagnostics

If a provider fails, the sidebar shows detailed diagnostics such as:

- Missing API key
- HTTP status code
- Provider error body
- Timeout or connection error
- Unexpected response format
- Gemini responses with no usable candidate

This makes debugging much easier than a generic "model failed" message.

## Notes

- Free-tier limits can change by provider.
- Provider availability can vary by region, account, quota, and rate limit.
- Keep API keys private and never commit `.env` files.
- Use paid models for final synthesis, complex reasoning, or high-value tasks where quality matters more than cost.

## Concept

The goal is not to avoid paid LLMs completely.

The goal is to avoid wasting paid tokens on tasks that free-tier models can handle.

Free-first routing is a simple cost-control pattern for token-heavy AI systems.
