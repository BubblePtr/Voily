export type SupportedApp = {
  iconPath: string
  name: string
}

export const apps: SupportedApp[] = [
  { iconPath: '/app-icons/cursor.svg', name: 'Cursor' },
  { iconPath: '/app-icons/vscode.svg', name: 'VS Code' },
  { iconPath: '/app-icons/slack.svg', name: 'Slack' },
  { iconPath: '/app-icons/notion.svg', name: 'Notion' },
  { iconPath: '/app-icons/gmail.svg', name: 'Gmail' },
  { iconPath: '/app-icons/wechat.svg', name: 'WeChat' },
  { iconPath: '/app-icons/chrome.svg', name: 'Chrome' },
  { iconPath: '/app-icons/chatgpt.svg', name: 'ChatGPT' }
]

export const openSourceBenefits = [
  {
    title: 'Transparent by default',
    copy:
      'Review the code behind recording, transcription, and text insertion before you trust it with your workflow.'
  },
  {
    title: 'Local when you want it',
    copy:
      'Use local ASR or bring your own cloud provider. Keep the setup aligned with your privacy needs.'
  },
  {
    title: 'Community-shaped',
    copy:
      'Issues, pull requests, and real workflow feedback guide what Voily becomes next.'
  },
  {
    title: 'Hackable on macOS',
    copy:
      'Tune shortcuts, providers, prompts, and native Mac behavior instead of waiting on a closed roadmap.'
  }
]
