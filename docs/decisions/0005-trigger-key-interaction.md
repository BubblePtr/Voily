---
date: 2026-04-19
status: accepted
tracks: []
---

# 触发键固定单击/双击语义，不开放快捷键自定义

## 背景

早期方案让用户自定义「按住录音 / 单击录音 / 双击翻译」等多种交互组合，配置面板复杂、用户认知负担重。同时 Fn 键的特殊性导致部分快捷键路径不可用。

## 决策

- **用户只选触发键**：当前提供 `Fn` 与 `右 Command` 两种选择（`TriggerKey` 枚举）。
- **交互语义固定**：
  - 单击触发键：开始 / 结束听写
  - 双击触发键：启动中→英快速翻译
- **手势状态机** 固定为 `idle → firstTapPressing → waitingForSecondTap → secondTapPressing → dictating`，集中在 `FnKeyMonitor`，不暴露给上层。
- **右 Command 组合键保护**：当 `event.modifierFlags` 包含其它修饰键（command / shift / option / control）时**不**触发 Voily，避免吞掉系统快捷键。
- **Fn 键监听走 IOKit**，不要替换为 `NSEvent` global monitor —— 后者拿不到 Fn 的按下/抬起。

## 放弃的方案

- **完全自定义快捷键**：UI 复杂、状态机分叉爆炸、与系统快捷键冲突难以收敛。
- **按住说话**：和「单击切换」混合提供时用户难以理解；且按住手势在某些键上系统会触发字符重复。

## 后果

- 正面：设置页只剩一个下拉框；新用户上手成本极低；右 Command 模式下不破坏正常快捷键体验。
- 负面：放弃了「按住对讲」类场景，重度听写用户偶有抱怨 —— 接受，可在未来基于真实需求再开口。
- 约束沉淀：CLAUDE.md「勿踩」中保留「Fn 键监听走 IOKit」一条。
