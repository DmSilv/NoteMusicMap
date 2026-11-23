# Plano de pagamento por Pix (Pro do professor)

Decidido em 23/11/2026. **Nada disso opera para ninguém ainda:** tudo nasce desligado e é só preparação.

## Decisões

| Tema | Decisão |
|---|---|
| Plano | **Pro Professor** (aluno é sempre grátis) |
| Preço | **R$ 14,90 por mês** ou **R$ 149 por ano** (2 meses grátis, desconto de ~17%) |
| Plano grátis | O professor usa de graça **até 3 alunos**; o Pro tira o limite e libera turmas, acervo e relatórios (a lista exata dos recursos do Pro ainda será fechada) |
| Meio de pagamento | **Somente Pix**, via **Mercado Pago** (sem cartão) |
| Modelo | **Pix avulso por período**: paga 30 dias ou 365 dias; o app avisa antes de vencer; sem renovação automática. (O Pix Automático existe no Mercado Pago, mas não achei documentação de API; fica como evolução.) |
| Conta que recebe | **CPF do Daniel**, para começar. Antes de ligar a cobrança: confirmar com o suporte do Mercado Pago se conta de pessoa física pode cobrar assim e **falar com um contador** sobre imposto (carnê-leão e Imposto de Renda). Software por assinatura não cabe no MEI. |
| Onde | **Só na web** por enquanto. No Android pela Play, assinatura digital deve usar o Google Play Billing (as lojas estão adiadas). |

## Contas (estimativa; preços de 12/11/2026, câmbio R$ 5,50)

- **Fixo por mês:** Vercel Pro (US$ 20 ≈ R$ 110, obrigatório quando há cobrança) + domínio ≈ **R$ 115 a R$ 120**. A IA não está nesta conta.
- **Variável:** R$ 0,01 a R$ 0,11 por usuário ativo; um professor com ~8 alunos custa de R$ 0,10 a R$ 1,00 por mês.
- **Taxa do Pix no Mercado Pago:** 0,99% no checkout (R$ 0,15 no mensal). Conferir na conta.
- **Equilíbrio:** cerca de **9 assinantes** a R$ 14,90 (antes do imposto).

| Assinantes | Receita/mês | Sobra aproximada antes do imposto |
|---|---|---|
| 50 | R$ 745 | R$ 590 |
| 100 | R$ 1.490 | R$ 1.300 |

## Como será feito (em etapas, tudo desligado)

1. **Servidor**: catálogo de planos; criar o Pix (QR e "copia e cola") pelo Mercado Pago com `external_reference` = código do professor + plano; receber o aviso de pagamento (webhook) **conferindo a assinatura**; buscar o pagamento e, se aprovado, somar 30 ou 365 dias a "Pro até" na conta. **Idempotente** (o mesmo pagamento nunca conta duas vezes). Custo: 3 a 5 comandos do Redis por pagamento; sem polling pesado.
2. **Limite de alunos** do plano grátis, decidido pelo servidor (o app só esconde).
3. **App**: tela "Plano" com os dois preços, Pix na hora, estado que atualiza sozinho (consulta barata) e "Pro até dd/mm"; aviso 5 dias antes de vencer (QStash).
4. **Painel admin**: lista de pagamentos e liberação manual do Pro (teste e cortesia).
5. **Chave de ligar e desligar**, desligada para todos. Testar primeiro com as credenciais de teste do Mercado Pago.
6. Política de reembolso e termos, antes de ligar.

## O que o Daniel precisa fazer

- Criar a aplicação no painel de desenvolvedores do Mercado Pago e gerar as **credenciais de teste**; depois as de produção.
- Guardar na Vercel (nunca em chat nem no repositório): `MP_ACCESS_TOKEN` e `MP_WEBHOOK_SECRET`.
- Perguntar ao suporte do Mercado Pago sobre uso de conta de pessoa física para cobrança recorrente de um serviço.
- Falar com um contador (imposto sobre a receita no CPF e quando abrir uma ME no Simples).

## Estado em 23/11/2026

- **Funcionando em produção:** gerar o Pix, aviso assinado, liberar o Pro uma vez, plano de teste de R$ 1 (pagamento real conferido: R$ 0,99 líquidos).
- **Pronto, ainda não publicado:** reembolso (7 dias pelo professor; qualquer hora pelo admin), histórico, tela **Plano** no app (selo Pro, "Pro até", renovar mensal e anual, reembolso), aba **Pagamentos** no painel e painel reorganizado em 7 áreas.
- **Falta:** limite de 3 alunos no grátis, aviso de vencimento (5 dias antes), acesso público à tela Plano (hoje toque longo no título de Minha conta) e política/termos.

## Pontos em aberto

- Lista final dos recursos do Pro.
- Política de reembolso (ex.: 7 dias) e texto dos termos.
- Nota fiscal: depende da conta de recebimento (CPF ou CNPJ).
