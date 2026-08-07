# Geração do arquivo `traffic_light_model.h`

Este README explica como gerar o arquivo `traffic_light_model.h`, utilizado pelo firmware para carregar os pesos, bias, entradas de teste e amostras do modelo de classificação de semáforo.

## Objetivo

O arquivo `traffic_light_model.h` é gerado a partir do script Python `train_traffic_light_export_v4.py`.

Esse script realiza o treinamento/exportação do modelo e cria um arquivo `.h` contendo os dados necessários para serem usados no firmware C da NPU/PicoRV32.

## Comando para gerar o arquivo

Execute o comando abaixo no terminal, dentro da pasta onde está localizado o script `train_traffic_light_export_v4.py`:

py train_traffic_light_export_v4.py --dataset . --out traffic_light_model.h --samples 8


## Explicação do comando

py train_traffic_light_export_v4.py --dataset . --out traffic_light_model.h --samples 8


### `py`

Executa o Python no Windows.

### `train_traffic_light_export_v4.py`

É o script responsável por treinar/exportar o modelo de semáforo e gerar o arquivo de saída em formato `.h`.

### `--dataset .`

Indica que o dataset está localizado na pasta atual.

O ponto `.` significa “diretório atual”.

### `--out traffic_light_model.h`

Define o nome do arquivo de saída que será gerado.

Neste caso, o script irá criar o arquivo:

traffic_light_model.h

### `--samples 8`

Define a quantidade de amostras que serão exportadas para validação/teste no firmware.

Neste caso, serão exportadas 8 amostras.

## Arquivo gerado

Após executar o comando, será criado o arquivo:

traffic_light_model.h

Esse arquivo deve ser incluído no firmware C para permitir que a CPU envie os dados do modelo para a NPU.

Exemplo de inclusão no firmware:

#include "traffic_light_model.h"

## Uso no firmware

O arquivo `traffic_light_model.h` contém os dados necessários para testar a inferência da NPU, como:

* pesos do modelo;
* bias;
* entradas de teste;
* labels esperados;
* amostras para validação.

Com isso, o firmware consegue carregar os dados na NPU, executar a inferência e comparar o resultado obtido com o resultado esperado.

## Fluxo geral

Dataset
   ↓
train_traffic_light_export_v4.py
   ↓
traffic_light_model.h
   ↓
Firmware C
   ↓
PicoRV32 envia dados para a NPU
   ↓
NPU executa a inferência
   ↓
CPU lê e valida o resultado


## Observação

Sempre que o dataset ou a quantidade de amostras for alterada, o arquivo `traffic_light_model.h` deve ser gerado novamente para manter o firmware atualizado com os dados corretos.
