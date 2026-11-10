# Catálogo de erros

> **Gerado automaticamente** por `scripts/gen_docs.js` a partir do código. Não edite à mão: rode `node scripts/gen_docs.js`.
> Lido de `packages/afina_core/lib/errors.dart` (`kErrorCatalog`). Para criar um erro novo, acrescente a entrada lá e rode o gerador.

| Código | Gravidade | Título | O que a pessoa lê | Ação |
|---|---|---|---|---|
| `NET-01` | info | Sem internet | Sem conexão agora. O que você fez fica guardado e é enviado quando a internet voltar. | Tentar de novo |
| `NET-02` | info | Servidor indisponível | O servidor não respondeu. Tudo continua funcionando neste aparelho; tente de novo daqui a pouco. | Tentar de novo |
| `NET-03` | action | Muitos pedidos | Foram muitos pedidos em pouco tempo. Aguarde um instante e tente de novo. | Tentar de novo |
| `API-04` | action | Pedido recusado | O servidor não aceitou este pedido. Confira os dados e tente de novo. | Tentar de novo |
| `API-05` | action | Erro no servidor | O servidor teve um problema ao responder. Tente de novo em instantes. | Tentar de novo |
| `DATA-01` | action | Dados inválidos | Os dados recebidos não estão no formato esperado. Nada foi alterado. | Voltar |
| `STO-01` | action | Armazenamento | Não foi possível guardar neste aparelho. Verifique o espaço livre e tente de novo. | Tentar de novo |
| `AUD-01` | action | Áudio | O áudio não pôde ser usado agora. Confira o microfone e as permissões do aparelho. | Tentar de novo |
| `UI-01` | action | Bloco não carregou | Uma parte desta tela não carregou. O resto continua funcionando. | Tentar de novo |
| `APP-00` | action | Algo não funcionou | Houve um erro inesperado. Você pode tentar de novo; se repetir, envie o relatório. | Tentar de novo |
| `APP-99` | critical | O app não conseguiu abrir | Algo impediu o app de iniciar. Seus dados continuam guardados neste aparelho. | Tentar de novo |

Total: **11** códigos. Gravidade: `critical` derruba o app (tela cheia), `action` é uma ação que falhou, `info` é só aviso de conexão.
