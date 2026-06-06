export type DemoExample = {
  app: string
  said: string
  writes: string
}

export type SupportedApp = {
  iconPath: string
  name: string
}

export const demoExamples: DemoExample[] = [
  {
    app: 'Slack',
    said: 'tell jason that api bug is fixed\nhe can pull the latest main branch',
    writes:
      'Hey Jason - the API bug has been fixed.\nPull the latest from main when you get a chance.'
  },
  {
    app: 'Cursor',
    said: 'this function cleans up the user input\nand saves it to the database',
    writes:
      '// Sanitizes raw user input and persists\n// the cleaned result to the database.'
  },
  {
    app: 'Gmail',
    said:
      "tell the client the project is delayed one week\nbecause we're waiting on a third party api",
    writes:
      "Hi - I wanted to give you a quick update on the timeline. We're currently waiting on a third-party API integration, which will push delivery back by approximately one week. I'll keep you posted on any changes."
  },
  {
    app: 'ChatGPT',
    said: 'write a prompt that makes gpt analyze\nthis csv and find outliers',
    writes:
      'Analyze the attached CSV file. Identify statistical outliers in each numeric column using the IQR method. Flag rows that contain outliers and explain why each value is anomalous.'
  }
]

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

export const capabilities = [
  {
    title: 'AI Rewrite',
    copy:
      'Say it rough, get it polished. Not autocorrect - a full rewrite that matches the tone your context needs.'
  },
  {
    title: 'Refine for the moment',
    copy:
      'Turn a spoken note into a concise code comment, a professional email, a casual message, or a structured prompt.'
  },
  {
    title: 'Always Ready',
    copy:
      'One shortcut, anywhere on your Mac. No app switching, no input panel, no copy-pasting.'
  }
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
