# Voily Landing Page V0 Scope

本文档记录本次官网 V0 的实现范围，以及刻意暂缓的内容。目标是让首版页面短、锋利、可上线，而不是把 README、截图和全部能力一次性塞进首页。

## V0 已纳入

- **Hero 极简首屏**：只保留产品名、下载入口、主标题、副标题、CTA 和小字说明。
- **Code-driven demo**：用前端动画展示 `You said` 到 `Voily writes` 的 before/after 转换，不依赖录屏或截图。
- **Works Everywhere**：保留一句核心主张 `If you can type there, you can speak there.`，并用纯文字列出典型应用。
- **Key Capabilities**：保留三项能力：AI Rewrite、Refine for the moment、Always Ready。
- **Final CTA + Footer**：用轻量 CTA 收尾，Footer 先只放 GitHub，避免使用未确认的联系邮箱。

## V0 暂缓

- **真实产品截图与设置页展示**：首版先不使用截图，避免页面变成产品说明书。等有更好的录屏或稳定视觉素材后再引入。
- **Hero 视频**：等有 15 秒真实录屏后再放到 V1；当前 demo 动画可以作为备用展示。
- **App logo/icon 横排**：首版用纯文字 app 名称。后续有统一 icon 资源后再补。
- **Provider 细节与模型列表**：SenseVoice、Doubao、Fun-ASR、Qwen、StepFun 等细节先放到 README/docs，不放首页主叙事。
- **权限细节**：Microphone、Accessibility、pasteboard injection、system audio mute 等先不进首页，后续可以放 FAQ 或 docs。
- **Social proof / Pricing**：首版不做。等有真实用户反馈、Product Hunt/Twitter 评价或商业策略后再加。
- **双语切换**：首版默认英文，不做未完成的语言切换控件。
- **复杂微动画**：能力卡内动画暂缓；首版只把主 demo 动画做好。

## 后续升级路径

### V1

- Hero 或 Demo 区接入真实 15 秒录屏。
- Works Everywhere 加统一风格 app icon。
- Key Capabilities 卡片加入轻量 CSS 微动画。
- 确认是否可写 `Free during beta`，并补充明确联系邮箱。

### V2

- 增加 Social Proof。
- 增加 FAQ，解释权限、本地模型、云端 provider、隐私边界。
- 视情况拆分 General / Developer 两套页面叙事。

## 当前需要确认

- `Free during beta` 是否确定可以写在首版；当前页面先不展示。
- Footer 的 Email 地址。
- 是否需要放 Twitter / X 链接，以及链接到个人账号还是项目账号。
