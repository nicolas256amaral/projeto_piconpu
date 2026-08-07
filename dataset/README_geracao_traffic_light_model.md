# Geração do `traffic_light_model.h`

Este documento descreve o processo de treinamento, quantização e exportação do modelo de classificação de semáforo utilizado pela NPU integrada ao PicoRV32.

O script principal é:

```text
train_traffic_light_export_v5.py
```

Ele gera os arquivos:

```text
traffic_light_model.h
traffic_light_preprocess.json
```

O primeiro arquivo é usado pelo firmware do PicoRV32. O segundo é usado pelo programa que converte imagens novas em 63 features quantizadas.

---

## 1. Objetivo

O treinamento classifica imagens de semáforo em duas classes:

```text
0 = red
1 = green
```

O fluxo completo é:

```text
dataset de imagens
    ↓
extração de características
    ↓
normalização
    ↓
treinamento do classificador
    ↓
quantização
    ↓
exportação dos pesos e parâmetros
    ↓
traffic_light_model.h
```

---

## 2. Estrutura esperada do dataset

A pasta informada em `--dataset` deve conter duas subpastas:

```text
dataset/
├── red/
│   ├── imagem_001.jpg
│   ├── imagem_002.jpg
│   └── ...
└── green/
    ├── imagem_001.jpg
    ├── imagem_002.jpg
    └── ...
```

Os nomes das pastas devem ser exatamente:

```text
red
green
```

As extensões aceitas são:

```text
.jpg
.jpeg
.png
.bmp
.webp
```

---

## 3. Organização recomendada

Exemplo:

```text
training/
├── train_traffic_light_export_v5.py
├── dataset/
│   ├── red/
│   └── green/
└── outputs/
```

Os arquivos de saída podem ser gerados diretamente na pasta `outputs`.

---

## 4. Dependências

É necessário ter o Python instalado.

Instale as bibliotecas:

```powershell
py -m pip install numpy opencv-python scikit-learn
```

Também pode ser usado:

```powershell
python -m pip install numpy opencv-python scikit-learn
```

---

## 5. Execução básica

Abra o PowerShell na pasta do script e execute:

```powershell
py train_traffic_light_export_v5.py `
  --dataset dataset `
  --out traffic_light_model.h `
  --preprocess-out traffic_light_preprocess.json `
  --samples 8
```

Em uma única linha:

```powershell
py train_traffic_light_export_v5.py --dataset dataset --out traffic_light_model.h --preprocess-out traffic_light_preprocess.json --samples 8
```

---

## 6. Significado dos parâmetros

### `--dataset`

Pasta que contém:

```text
red/
green/
```

Exemplo:

```powershell
--dataset dataset
```

---

### `--out`

Nome do header C gerado:

```powershell
--out traffic_light_model.h
```

Esse arquivo será incluído no firmware.

---

### `--preprocess-out`

Nome do JSON com os parâmetros de pré-processamento:

```powershell
--preprocess-out traffic_light_preprocess.json
```

Esse arquivo será usado por:

```text
image_to_uart_features.py
```

para converter imagens novas em features compatíveis com o modelo.

---

### `--samples`

Quantidade de amostras de teste incorporadas ao header.

Exemplo:

```powershell
--samples 8
```

Isso gera:

```c
#define TL_NUM_TEST_SAMPLES 8u
```

e inclui no header:

```c
tl_inputs
tl_expected_labels
```

Para gerar um header menor, sem amostras internas:

```powershell
--samples 0
```

Essa opção é recomendada quando a entrada será recebida apenas pela UART.

---

## 7. Comando recomendado para simulação

Para manter as amostras internas usadas na validação:

```powershell
py train_traffic_light_export_v5.py `
  --dataset dataset `
  --out traffic_light_model.h `
  --preprocess-out traffic_light_preprocess.json `
  --samples 8
```

---

## 8. Comando recomendado para uso dinâmico

Quando as imagens novas forem convertidas por `image_to_uart_features.py`:

```powershell
py train_traffic_light_export_v5.py `
  --dataset dataset `
  --out traffic_light_model.h `
  --preprocess-out traffic_light_preprocess.json `
  --samples 0
```

Nesse modo, o firmware fica menor porque não carrega as amostras de teste internas.

---

## 9. Pré-processamento das imagens

Durante o treinamento, cada imagem passa pelas seguintes etapas:

```text
leitura da imagem
    ↓
conversão BGR → RGB
    ↓
redimensionamento para 24 × 72
    ↓
recorte central de 35% da largura
    ↓
normalização de iluminação com CLAHE
    ↓
extração das 63 features
```

As 63 features incluem informações como:

- média dos canais RGB;
- proporções normalizadas de vermelho e verde;
- diferenças `R - G` e `G - R`;
- proporção de pixels vermelhos e verdes;
- intensidade média das regiões;
- picos de intensidade;
- posição vertical das cores;
- média de saturação;
- média de brilho;
- diferenças entre regiões superior e inferior.

A imagem é dividida em três regiões:

```text
top
middle
bottom
```

Isso permite capturar a posição vertical da luz acesa.

---

## 10. Treinamento

O script utiliza:

```text
LogisticRegression
```

com busca por diferentes valores de `C`.

Exemplos avaliados:

```text
0.03
0.05
0.1
0.3
1.0
3.0
10.0
30.0
```

O melhor valor é escolhido com base na acurácia do conjunto de teste.

O modelo utiliza:

```text
solver = lbfgs
class_weight = balanced
max_iter = 4000
```

O balanceamento ajuda quando a quantidade de imagens de uma classe é diferente da outra.

---

## 11. Normalização

Antes do treinamento, as features são normalizadas com:

```text
StandardScaler
```

Para cada feature:

```text
feature_normalizada =
    (feature_bruta - média)
    / desvio_padrão
```

Os parâmetros são exportados para:

```text
traffic_light_preprocess.json
```

nos campos:

```json
"scaler_mean": [...]
"scaler_scale": [...]
```

---

## 12. Quantização

A NPU trabalha com valores inteiros de 8 bits.

Por isso, pesos e entradas são convertidos para:

```text
int8
```

Intervalo permitido:

```text
-128 a 127
```

O processo é:

```text
valor_float
    ↓
multiplicação pela escala
    ↓
arredondamento
    ↓
saturação entre -128 e 127
```

A escala das entradas também é exportada para o JSON:

```json
"input_quant_scale": ...
```

---

## 13. Geração do `traffic_light_model.h`

O header contém:

```c
#define TL_NUM_CLASSES
#define TL_FEATURE_DIM
#define TL_K_DIM
#define TL_QUANT_CFG
#define TL_QUANT_MULT
#define TL_NUM_TEST_SAMPLES
```

Também contém:

```c
tl_bias
tl_weights
```

Quando `--samples` é maior que zero, também contém:

```c
tl_inputs
tl_class_names
tl_expected_labels
```

Exemplo:

```c
#define TL_NUM_CLASSES 2u
#define TL_FEATURE_DIM 63u
#define TL_K_DIM 63u
#define TL_QUANT_CFG 0x00000010u
#define TL_QUANT_MULT 0x000088CFu
```

---

## 14. Organização dos pesos

Cada posição de:

```c
tl_weights
```

é uma word de 32 bits.

Cada byte representa o peso de uma classe ou canal da NPU.

Exemplo:

```c
0x000000FFu
```

O byte menos significativo é:

```text
0xFF = -1 em int8
```

Outro exemplo:

```c
0x00000001u
```

representa:

```text
1
```

---

## 15. Geração do `traffic_light_preprocess.json`

O JSON contém:

```text
class_names
class_to_id
image_size
central_crop_frac_w
feature_dim
scaler_mean
scaler_scale
input_quant_scale
quantization
npu_output
training
```

Esse arquivo não é compilado no firmware.

Ele é usado fora do PicoRV32 para processar imagens novas.

Exemplo de uso:

```text
image.jpg
    ↓
image_to_uart_features.py
    ↓
traffic_light_preprocess.json
    ↓
63 features quantizadas
    ↓
UART
```

---

## 16. Arquivos gerados

Após uma execução bem-sucedida:

```text
traffic_light_model.h
traffic_light_preprocess.json
```

Opcionalmente, dependendo dos argumentos usados:

```text
uart_sample.hex
```

---

## 17. Uso do header no firmware

Copie:

```text
traffic_light_model.h
```

para a pasta usada pelo compilador do firmware.

Exemplo:

```text
common/traffic_light_model.h
```

Depois gere novamente:

```text
firmware.hex
```

Fluxo:

```text
traffic_light_model.h
    ↓
compilação RISC-V
    ↓
firmware.elf
    ↓
firmware.bin
    ↓
firmware.hex
```

Sempre que o modelo for gerado novamente, o firmware também precisa ser recompilado.

---

## 18. Uso do JSON

Coloque:

```text
traffic_light_preprocess.json
```

na mesma pasta de:

```text
image_to_uart_features.py
```

Estrutura:

```text
image_to_uart/
├── image_to_uart_features.py
├── traffic_light_preprocess.json
└── image.jpg
```

Execute:

```powershell
py image_to_uart_features.py --image image.jpg
```

---

## 19. Validação da saída do treinamento

Ao final da execução, o script apresenta informações como:

```text
Melhor C
Relatório de classificação
Acurácia float
Acurácia quantizada
Matriz de confusão
quant_mult
quant_cfg
```

É importante observar principalmente:

```text
accuracy_float
accuracy_quantized
```

A diferença entre esses valores mostra a perda causada pela quantização.

Exemplo:

```text
accuracy_float     = 0.8462
accuracy_quantized = 0.6923
```

Nesse caso, o modelo float teve desempenho superior ao modelo quantizado.

---

## 20. Compatibilidade entre arquivos

Estes arquivos devem sempre ser gerados juntos:

```text
traffic_light_model.h
traffic_light_preprocess.json
```

Eles precisam pertencer ao mesmo treinamento.

Não utilize:

```text
header de um treinamento
+
JSON de outro treinamento
```

Isso pode gerar features incompatíveis com os pesos da NPU.

---

## 21. Erros comuns

### Pasta `red` ou `green` não encontrada

Erro típico:

```text
Pasta não encontrada
```

Confirme a estrutura:

```text
dataset/red
dataset/green
```

---

### Nenhuma imagem encontrada

Confirme se as imagens possuem extensões aceitas:

```text
.jpg
.jpeg
.png
.bmp
.webp
```

---

### Poucas imagens por classe

O `train_test_split` usa estratificação.

Se houver poucas imagens, pode ocorrer erro porque não é possível separar corretamente treino e teste.

Adicione mais imagens em cada classe.

---

### Acurácia muito baixa

Possíveis causas:

- poucas imagens;
- iluminação muito diferente;
- semáforo fora da região central;
- imagens com enquadramento inconsistente;
- classes desbalanceadas;
- ruído de fundo;
- luz vermelha ou verde pouco visível.

---

### Acurácia quantizada muito menor

Isso indica perda significativa na conversão para int8.

Possíveis melhorias:

- aumentar o dataset;
- separar conjunto de calibração;
- rever a escala de quantização;
- testar quantização separada para pesos e inputs;
- usar mais features relevantes;
- remover features instáveis;
- ajustar o classificador.

---

### Header não muda

Confirme que o comando está escrevendo no caminho correto:

```powershell
--out traffic_light_model.h
```

Apague o arquivo antigo e execute novamente.

---

## 22. Conferência rápida

Depois da geração, confirme no header:

```c
#define TL_FEATURE_DIM 63u
#define TL_K_DIM 63u
```

Confira também:

```c
static const int32_t tl_bias[4]
static const uint32_t tl_weights[TL_K_DIM]
```

No JSON, confirme:

```json
"feature_dim": 63
```

e:

```json
"input_quant_scale": ...
```

---

## 23. Procedimento resumido

```text
1. Organizar dataset/red e dataset/green
2. Instalar numpy, opencv-python e scikit-learn
3. Executar train_traffic_light_export_v5.py
4. Gerar traffic_light_model.h
5. Gerar traffic_light_preprocess.json
6. Copiar o header para common/
7. Recompilar o firmware
8. Copiar o JSON para a pasta do conversor de imagens
9. Gerar as features de image.jpg
10. Executar a simulação
```

Comando principal:

```powershell
py train_traffic_light_export_v5.py `
  --dataset dataset `
  --out traffic_light_model.h `
  --preprocess-out traffic_light_preprocess.json `
  --samples 8
```

Arquivos finais:

```text
traffic_light_model.h
traffic_light_preprocess.json
```
