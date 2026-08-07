# Geração do Firmware para o PicoRV32 + NPU

Este documento descreve o processo de geração do `firmware.hex` utilizado pelo SoC baseado em PicoRV32 com integração AXI e NPU.

O firmware é responsável por:

- inicializar a NPU;
- carregar pesos, bias e parâmetros de quantização;
- receber as 63 features pela UART;
- executar a inferência;
- ler o resultado da NPU;
- devolver a classificação pela UART;
- gerar o arquivo `firmware.hex` carregado pelo bootloader na simulação.

---

## 1. Estrutura esperada do projeto

Uma organização típica é:

```text
piconpu/
├── firmware.hex
├── traffic_light_preprocess.json
├── common/
│   ├── crt0.S
│   ├── linker.ld
│   ├── Makefile
│   ├── bin2memh_word32.py
│   ├── traffic_light_model.h
│   ├── npu_test.c
│   └── npu_test.h
├── test/
│   ├── tb_soc_top.v
│   └── run_modelsim.do
└── test/
    └── GROUP/
        └── COMPLETE/
            └── main.c
```

A estrutura exata pode variar, mas os arquivos principais precisam estar acessíveis pelo comando de compilação.

---

## 2. Arquivos necessários

### `traffic_light_model.h`

Contém os parâmetros exportados pelo treinamento:

```text
TL_FEATURE_DIM
TL_K_DIM
TL_QUANT_CFG
TL_QUANT_MULT
tl_bias
tl_weights
tl_inputs
tl_expected_labels
```

Esse arquivo deve ser gerado pelo script de treinamento:

```powershell
py train_traffic_light_export_v5.py `
  --dataset . `
  --out traffic_light_model.h `
  --preprocess-out traffic_light_preprocess.json `
  --samples 8
```

Depois, copie o header para a pasta usada pelo firmware, normalmente:

```text
common/traffic_light_model.h
```

Não combine um `traffic_light_model.h` de um treinamento com um `traffic_light_preprocess.json` de outro treinamento.

---

### `npu_test.c`

Contém a lógica de controle da NPU, incluindo:

- escrita dos registradores;
- configuração da dimensão `K`;
- configuração da quantização;
- carregamento dos bias;
- carregamento dos pesos;
- envio das features;
- comando de início;
- espera pelo sinal de conclusão;
- leitura das saídas.

Fluxo simplificado:

```text
reset da NPU
    ↓
configuração de K
    ↓
quantização
    ↓
bias
    ↓
pesos + features
    ↓
START
    ↓
espera DONE
    ↓
leitura do resultado
```

---

### `main.c`

O `main.c` chama a função principal do firmware.

Exemplo:

```c
#include "npu_test.h"

int main(void)
{
    npu_example();

    while (1) {
    }

    return 0;
}
```

No modo UART dinâmico, a função chamada pode ficar aguardando um pacote de entrada antes de iniciar a inferência.

---

### `crt0.S`

Realiza a inicialização mínima do processador:

- configura o stack pointer;
- inicializa memória quando necessário;
- chama `main`;
- mantém a CPU em loop ao final.

---

### `linker.ld`

Define o mapa de memória do firmware.

Exemplo de regiões normalmente utilizadas:

```text
RAM do sistema: 0x00000000
NPU AXI:        0x60000000
```

O linker deve posicionar código, constantes e dados dentro da RAM disponível.

---

### `bin2memh_word32.py`

Converte o binário final para o formato hexadecimal de 32 bits usado pelo bootloader e pela simulação.

Cada linha do `firmware.hex` representa uma word de 32 bits:

```text
00001117
00010113
10c000ef
0000006f
```

---

## 3. Toolchain necessária

O firmware é compilado para:

```text
Arquitetura: RV32I
ABI:         ILP32
```

É necessário ter uma toolchain RISC-V instalada.

Exemplo usado no Windows:

```text
C:\riscv\bin\riscv-none-elf-gcc.exe
```

Comandos esperados:

```text
riscv-none-elf-gcc
riscv-none-elf-objcopy
riscv-none-elf-objdump
```

Verifique a instalação:

```powershell
C:\riscv\bin\riscv-none-elf-gcc.exe --version
```

---

## 4. Compilação manual

Abra o PowerShell na pasta do projeto.

Exemplo de compilação direta:

```powershell
C:\riscv\bin\riscv-none-elf-gcc.exe `
  -march=rv32i `
  -mabi=ilp32 `
  -Os `
  -ffreestanding `
  -nostdlib `
  -nostartfiles `
  -I common `
  -T common\linker.ld `
  common\crt0.S `
  common\npu_test.c `
  test\GROUP\COMPLETE\main.c `
  -o firmware.elf
```

Depois gere o binário:

```powershell
C:\riscv\bin\riscv-none-elf-objcopy.exe `
  -O binary `
  firmware.elf `
  firmware.bin
```

Converta para HEX de 32 bits:

```powershell
py common\bin2memh_word32.py `
  firmware.bin `
  firmware.hex
```

---

## 5. Compilação com arquivo `.bat`

Para facilitar, pode ser utilizado um arquivo como:

```text
build_firmware.bat
```

Exemplo:

```bat
@echo off
setlocal

set RISCV=C:\riscv\bin
set COMMON=common
set APP=test\GROUP\COMPLETE

"%RISCV%\riscv-none-elf-gcc.exe" ^
  -march=rv32i ^
  -mabi=ilp32 ^
  -Os ^
  -ffreestanding ^
  -nostdlib ^
  -nostartfiles ^
  -I "%COMMON%" ^
  -T "%COMMON%\linker.ld" ^
  "%COMMON%\crt0.S" ^
  "%COMMON%\npu_test.c" ^
  "%APP%\main.c" ^
  -o firmware.elf

if errorlevel 1 goto error

"%RISCV%\riscv-none-elf-objcopy.exe" ^
  -O binary ^
  firmware.elf ^
  firmware.bin

if errorlevel 1 goto error

py "%COMMON%\bin2memh_word32.py" firmware.bin firmware.hex

if errorlevel 1 goto error

echo.
echo Firmware gerado com sucesso:
echo %CD%\firmware.hex
goto end

:error
echo.
echo ERRO durante a geracao do firmware.
exit /b 1

:end
endlocal
```

Execute:

```powershell
.\build_firmware.bat
```

---

## 6. Atualização do modelo

Sempre que o modelo for treinado novamente:

1. gere um novo `traffic_light_model.h`;
2. substitua o arquivo antigo em `common`;
3. compile novamente o firmware;
4. gere um novo `firmware.hex`;
5. execute novamente a simulação.

Fluxo:

```text
dataset
    ↓
train_traffic_light_export_v5.py
    ↓
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

---

## 7. Conferência do tamanho do firmware

O bootloader deve ter capacidade suficiente para receber todo o arquivo.

No projeto atual, o bootloader foi configurado com:

```verilog
.MEM_WORDS(1024)
```

Isso corresponde a:

```text
1024 words × 4 bytes = 4096 bytes
```

Para conferir a quantidade de linhas do `firmware.hex`:

```powershell
$words = (Get-Content .\firmware.hex | Measure-Object -Line).Lines
$words
```

O valor deve ser menor ou igual à capacidade configurada:

```text
words do firmware <= MEM_WORDS
```

Exemplo:

```text
firmware.hex = 1023 linhas
MEM_WORDS    = 1024
```

Nesse caso, o firmware cabe na memória do bootloader.

Caso o firmware ultrapasse o limite, aumente o valor de `MEM_WORDS` no bootloader e confirme que a RAM também possui capacidade suficiente.

---

## 8. Conferência do conteúdo gerado

### Verificar se o header foi incorporado

Após gerar o `firmware.hex`, confira se os pesos esperados aparecem no arquivo.

Exemplos conhecidos:

```text
000000ff
000000fe
00000001
```

No projeto atual, alguns pesos foram observados em índices após 255, por isso o bootloader precisou ser aumentado para 1024 words.

---

### Gerar desassembly

Para verificar o código compilado:

```powershell
C:\riscv\bin\riscv-none-elf-objdump.exe `
  -D `
  firmware.elf `
  > firmware_disassembly.txt
```

Também pode ser usado:

```powershell
C:\riscv\bin\riscv-none-elf-objdump.exe `
  -h `
  firmware.elf
```

para visualizar as seções e seus endereços.

---

## 9. Uso no ModelSim

Depois de gerar o `firmware.hex`, coloque o arquivo no caminho esperado pela testbench.

Exemplo:

```text
piconpu/firmware.hex
```

A testbench transmite o firmware ao `boot_manager` pela UART de boot.

Fluxo:

```text
firmware.hex
    ↓
testbench
    ↓
uart_rom_receiver
    ↓
boot_manager
    ↓
axi_ram
    ↓
cpu_resetn liberado
    ↓
PicoRV32 executa o firmware
```

No log, devem aparecer mensagens semelhantes a:

```text
TB: boot_mode ativado.
TB: boot_mgr.rom_done = 1. Firmware recebido.
TB: boot_mode desativado.
CPU: cpu_resetn liberado.
```

---

## 10. Conferência do boot

Para validar se o modelo foi realmente carregado na RAM, podem ser usados monitores na testbench.

Exemplo:

```verilog
$display("RAM peso[0] = 0x%08h", uut.ram_inst.mem[321]);
$display("RAM peso[3] = 0x%08h", uut.ram_inst.mem[324]);
$display("RAM peso[9] = 0x%08h", uut.ram_inst.mem[330]);
```

Resultado esperado no modelo validado:

```text
RAM peso[0] = 0x00000000
RAM peso[3] = 0x000000ff
RAM peso[9] = 0x000000fe
```

---

## 11. Resultado esperado da inferência

Com a amostra 0 previamente validada:

```text
predicted_label = 1
score_red       = 0
score_green     = 115
```

Resultado:

```text
RESULTADO DO PROTOCOLO: PASS
CLASSIFICACAO AMOSTRA 0: PASS
```

Mapeamento:

```text
0 = red
1 = green
```

---

## 12. Erros comuns

### Pesos chegando zerados na NPU

Possíveis causas:

- `traffic_light_model.h` antigo;
- firmware não recompilado;
- `firmware.hex` antigo ainda sendo usado;
- bootloader copiando menos words que o necessário;
- caminho incorreto para o header;
- arquivo gerado em outra pasta.

Verifique:

```text
MEM_WORDS
quantidade de linhas do firmware.hex
índices da RAM após o boot
writes em NPU_WEIGHT
```

---

### `firmware.hex` não muda

Apague os arquivos antigos:

```powershell
Remove-Item firmware.elf, firmware.bin, firmware.hex -ErrorAction SilentlyContinue
```

Depois compile novamente.

---

### Header não encontrado

Erro típico:

```text
fatal error: traffic_light_model.h: No such file or directory
```

Confirme que o comando contém:

```text
-I common
```

e que o arquivo está em:

```text
common/traffic_light_model.h
```

---

### Erro de arquitetura ou ABI

Confirme:

```text
-march=rv32i
-mabi=ilp32
```

Esses parâmetros devem ser compatíveis com o PicoRV32 configurado no projeto.

---

### Firmware maior que o bootloader

Aumente:

```verilog
.MEM_WORDS(1024)
```

para um valor maior, como:

```verilog
.MEM_WORDS(2048)
```

e ajuste também os módulos internos que usam o mesmo limite.

---

## 13. Procedimento resumido

```text
1. Treinar o modelo
2. Gerar traffic_light_model.h
3. Copiar o header para common/
4. Executar build_firmware.bat
5. Conferir firmware.hex
6. Conferir quantidade de words
7. Executar ModelSim
8. Conferir os pesos na RAM
9. Conferir NPU_WEIGHT
10. Conferir PASS da classificação
```

Comando principal:

```powershell
.\build_firmware.bat
```

Arquivo final:

```text
firmware.hex
```

Esse é o arquivo carregado pelo bootloader e executado pelo PicoRV32.
