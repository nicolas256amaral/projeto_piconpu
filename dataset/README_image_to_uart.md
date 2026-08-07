# Conversão de Imagem para Entrada UART da NPU

Este diretório contém o script `image_to_uart_features.py`, responsável por converter uma imagem de semáforo em um vetor de **63 features quantizadas**, compatível com o modelo `traffic_light_model.h` executado pela NPU integrada ao PicoRV32.

## Objetivo

O script realiza o seguinte fluxo:

```text
image.jpg
    ↓
Redimensionamento e recorte central
    ↓
Extração de 63 características
    ↓
Normalização com traffic_light_preprocess.json
    ↓
Quantização para int8
    ↓
Geração dos arquivos de entrada UART
```

## Arquivos necessários

Coloque os arquivos abaixo na mesma pasta:

```text
image_to_uart_features.py
traffic_light_preprocess.json
image.jpg
```

A imagem usada como entrada deve obrigatoriamente ter o nome:

```text
image.jpg
```

A estrutura recomendada é:

```text
image_to_uart/
├── image_to_uart_features.py
├── traffic_light_preprocess.json
└── image.jpg
```

## Formato da imagem

A imagem pode ter qualquer resolução original. O script realiza internamente:

- leitura em RGB;
- redimensionamento para `24 × 72` pixels;
- recorte central de 35% da largura;
- normalização de iluminação;
- extração das 63 features usadas no treinamento.

A imagem deve mostrar o semáforo preferencialmente centralizado e com as luzes vermelha e verde visíveis na região central.

## Dependências

É necessário ter o Python instalado.

Instale as bibliotecas utilizadas pelo script:

```powershell
py -m pip install numpy opencv-python
```

O `tkinter` normalmente já acompanha a instalação padrão do Python no Windows, mas ele não será necessário quando a imagem for informada diretamente pelo comando.

## Execução

Abra o PowerShell ou o Prompt de Comando na pasta dos arquivos e execute:

```powershell
py image_to_uart_features.py --image image.jpg
```

O script utilizará:

```text
traffic_light_preprocess.json
```

como configuração padrão de pré-processamento.

## Arquivos gerados

Após a execução, serão criados três arquivos.

### `uart_sample.hex`

Contém somente as 63 features quantizadas, uma por linha:

```text
0C
14
11
F7
...
```

Cada linha representa um byte enviado à NPU.

Valores negativos em `int8` são representados em complemento de dois:

```text
  1  → 01
 -1  → FF
 -2  → FE
-128 → 80
```

Este arquivo é indicado quando a testbench já constrói o cabeçalho e o checksum do protocolo UART.

### `uart_packet.hex`

Contém o pacote UART completo:

```text
A5
01
00
3F
<63 bytes de features>
<checksum>
```

Estrutura do pacote:

| Posição | Campo | Descrição |
|---:|---|---|
| 0 | `0xA5` | Byte de sincronismo |
| 1 | `0x01` | Versão do protocolo |
| 2 | `0x00` | Identificador da amostra |
| 3 | `0x3F` | Quantidade de features: 63 |
| 4–66 | Features | Valores quantizados em `int8` |
| 67 | Checksum | XOR dos campos do protocolo |

O byte de sincronismo `0xA5` não participa do cálculo do checksum.

### `uart_image_report.csv`

Contém um relatório para conferência:

```text
index,raw_feature,quantized_int8,uart_byte
```

Para cada uma das 63 features, o arquivo mostra:

- valor bruto extraído da imagem;
- valor quantizado entre `-128` e `127`;
- byte correspondente enviado pela UART.

## Identificador da amostra

Por padrão, o `sample_id` é zero.

Para usar outro identificador:

```powershell
py image_to_uart_features.py --image image.jpg --sample-id 1
```

O valor deve estar entre `0` e `255`.

## Nomes personalizados para os arquivos de saída

Os nomes podem ser alterados:

```powershell
py image_to_uart_features.py `
  --image image.jpg `
  --sample-out minha_amostra.hex `
  --packet-out meu_pacote.hex `
  --report-out meu_relatorio.csv
```

## Uso no ModelSim

Há duas formas de utilizar a imagem processada.

### Testbench que envia somente as features

Use:

```text
uart_sample.hex
```

A testbench deve montar:

```text
SYNC + VERSION + SAMPLE_ID + LENGTH + FEATURES + CHECKSUM
```

### Testbench que lê o pacote completo

Use:

```text
uart_packet.hex
```

Nesse caso, a testbench deve transmitir os bytes exatamente na ordem em que aparecem no arquivo.

## Fluxo completo do sistema

```text
image.jpg
    ↓
image_to_uart_features.py
    ↓
uart_sample.hex ou uart_packet.hex
    ↓
UART da testbench
    ↓
PicoRV32
    ↓
Pesos e features enviados para a NPU
    ↓
Inferência
    ↓
Resultado retornado pela UART
```

## Resultado esperado no terminal

Uma execução bem-sucedida apresenta uma saída semelhante a:

```text
Conversão concluída.
Imagem:            ...\image.jpg
Features geradas:  63
Intervalo int8:    -128 a 127
Checksum:          0xXX
Amostra HEX:       ...\uart_sample.hex
Pacote UART HEX:   ...\uart_packet.hex
Relatório:         ...\uart_image_report.csv
Classes do modelo: 0=red, 1=green
```

O intervalo real dependerá da imagem processada.

## Erros comuns

### JSON não encontrado

```text
ERRO: JSON não encontrado: traffic_light_preprocess.json
```

Confirme que o JSON está na mesma pasta do script.

### Imagem não encontrada

```text
ERRO: Imagem não encontrada: image.jpg
```

Confirme que:

- o arquivo está na mesma pasta;
- o nome é exatamente `image.jpg`;
- a extensão não está duplicada, como `image.jpg.jpg`.

No Windows, habilite a exibição das extensões dos arquivos para conferir o nome real.

### OpenCV não consegue abrir a imagem

Confirme que `image.jpg` é uma imagem válida e não está corrompida.

### Dimensão das features diferente de 63

O `traffic_light_preprocess.json` precisa ter sido gerado pela mesma versão do treinamento utilizada para produzir o `traffic_light_model.h`.

## Compatibilidade do modelo

Os arquivos abaixo devem sempre pertencer ao mesmo treinamento:

```text
traffic_light_model.h
traffic_light_preprocess.json
```

Não combine o header de um treinamento com o JSON de outro. Isso pode produzir features incompatíveis com os pesos carregados na NPU, mesmo que o protocolo UART funcione corretamente.
