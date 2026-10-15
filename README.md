# Claude Usage Overlay

Mostra o seu uso do Claude (sessão de 5h e limite semanal) de três jeitos, para Windows:

| Pasta | O que é | Precisa do Chrome? |
|---|---|---|
| `overlay/` | Janelinha nativa, transparente, sempre por cima, com clique atravessando | Não |
| `extensao/` | Extensão do Chrome: número no ícone, painel e widget dentro do claude.ai | Sim |
| `terminal/` | Statusline do Claude Code com 5h / semana / contexto | Não |

> **Projeto independente, não afiliado à Anthropic.** Ele lê o mesmo endereço interno de uso que a página
> *Configurações > Uso* do claude.ai usa. Esse endereço não é uma API documentada e pode mudar sem aviso.

## Overlay (recomendado)

Requisitos: Windows 10/11 com o WebView2 Runtime (já vem no Windows 11) e PowerShell 5.1.

1. Baixe o repositório (**Code > Download ZIP**) e extraia numa pasta fixa.
2. Dê dois cliques em **`Abrir overlay.cmd`**. Na primeira vez ele baixa os componentes oficiais do WebView2
   (assinatura digital da Microsoft conferida).
3. Uma janela **"Entrar no claude.ai"** abre. Entre na sua conta (prefira o login por e-mail com código; o login
   com Google costuma ser bloqueado em janelas embutidas). Depois do login a janela se esconde sozinha.

O overlay atualiza a cada 1 minuto e fica no canto inferior direito.

**Ícone da bandeja** (perto do relógio; clique com o botão direito):
- *Mover janela*: clique esquerdo no ícone para destravar, arraste, clique de novo para travar.
- *Mais / Menos transparente*, *Voltar ao canto da tela*.
- *Entrar / trocar conta*, *Sair da conta (apagar login)*, *Sair*.

Posição e transparência ficam salvas em `%APPDATA%\ClaudeUsageOverlay\config.json`.

### Segurança e privacidade
- O login fica só na sua máquina, na pasta de dados do WebView2 (`%APPDATA%\ClaudeUsageOverlay\webview`), com cookies
  cifrados pelo Windows para o seu usuário. Nada é enviado a terceiros.
- O programa também escuta em `127.0.0.1:47831` para receber dados da extensão (opcional). Só aceita conexões locais.
- Os scripts rodam com `-ExecutionPolicy Bypass` apenas nessa execução. Leia o código antes de rodar: são arquivos pequenos.

## Extensão do Chrome

1. `chrome://extensions` > ativar **Modo do desenvolvedor** > **Carregar sem compactação** > escolher a pasta `extensao`.
2. O ícone mostra a % da sessão de 5h (verde, amarelo, vermelho). Clique nele para ver o painel.
3. Também aparece um widget no canto do claude.ai.

Permissões: só `https://claude.ai/*` e `127.0.0.1:47831` (para alimentar o overlay), mais `alarms` e `storage`.
Sem `cookies`: as requisições usam a sessão que o próprio Chrome já tem.

Status dos testes: o widget dentro do claude.ai foi confirmado funcionando. O ícone com número e a janela
"por cima" (Picture-in-Picture) foram testados só em simulação.

## Statusline do Claude Code

1. Copie `terminal/statusline.ps1` para `~/.claude/`.
2. Acrescente ao `~/.claude/settings.json` (cuidado com as vírgulas):

```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -File ~/.claude/statusline.ps1",
  "refreshInterval": 30
}
```

Mostra `5h 25% (3h21) | 7d 11% (2d3h) | ctx 8%`. Os dados vêm do próprio Claude Code, então só atualizam depois de
cada resposta (não é ao vivo) e só aparecem para assinantes Pro/Max.

## Limitações
- Só Windows (o overlay e os scripts usam WPF/PowerShell).
- Sem licença definida por enquanto: todos os direitos reservados ao autor até que uma seja adicionada.
