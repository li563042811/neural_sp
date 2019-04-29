#!/bin/bash

# Copyright 2018 Kyoto University (Hirofumi Inaguma)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

echo ============================================================================
echo "                                   CSJ                                     "
echo ============================================================================

stage=0
gpu=

### vocabulary
unit=wp           # word/wp/word_char
vocab_size=30000
wp_type=bpe       # bpe/unigram (for wordpiece)
unit_sub1=wp
wp_type_sub1=bpe  # bpe/unigram (for wordpiece)
vocab_size_sub1=5000
unit_sub2=char
wp_type_sub2=bpe  # bpe/unigram (for wordpiece)
vocab_size_sub2=

#########################
# ASR configuration
#########################
### topology
n_splices=1
n_stacks=1
n_skips=1
conv_in_channel=1
conv_channels=
conv_kernel_sizes=
conv_strides=
conv_poolings=
conv_batch_norm=false
conv_bottleneck_dim=0
subsample="1_2_2_2_1"
# VGG
# conv_channels="64_64_128_128"
# conv_kernel_sizes="(3,3)_(3,3)_(3,3)_(3,3)"
# conv_strides="(1,1)_(1,1)_(1,1)_(1,1)"
# conv_poolings="(1,1)_(2,2)_(1,1)_(2,2)"
# subsample="1_1_1_1_1"
enc_type=blstm
enc_n_units=512
enc_n_projs=0
enc_n_layers=5
enc_n_layers_sub1=4
enc_n_layers_sub2=3
enc_residual=false
subsample_type=drop
attn_type=location
attn_dim=512
attn_n_heads=1
attn_sigmoid=false
dec_type=lstm
dec_n_units=1024
dec_n_projs=0
dec_n_layers=1
dec_loop_type=normal
dec_residual=false
input_feeding=false
dec_bottleneck_dim=1024
emb_dim=512
tie_embedding=false
ctc_fc_list="512"
ctc_fc_list_sub1="512"
ctc_fc_list_sub2="512"
### optimization
batch_size=40
optimizer=adam
learning_rate=1e-3
n_epochs=25
convert_to_sgd_epoch=20
print_step=200
decay_start_epoch=10
decay_rate=0.85
decay_patient_n_epochs=0
decay_type=epoch
not_improved_patient_n_epochs=5
eval_start_epoch=1
warmup_start_learning_rate=1e-4
warmup_n_steps=0
### initialization
param_init=0.1
param_init_dist=uniform
pretrained_model=
### regularization
clip_grad_norm=5.0
dropout_in=0.0
dropout_enc=0.4
dropout_dec=0.4
dropout_emb=0.4
dropout_att=0.0
weight_decay=1e-6
ss_prob=0.2
ss_type=constant
lsm_prob=0.1
layer_norm=false
focal_loss=0.0
adaptive_softmax=false
### MTL
ctc_weight=0.0
ctc_weight_sub1=0.2
ctc_weight_sub2=0.2
bwd_weight=0.0
sub1_weight=0.2
sub2_weight=0.2
mtl_per_batch=true
task_specific_layer=true
### LM integration
lm_fusion_type=cold
lm_fusion=
lm_init=
lmobj_weight=0.0
share_lm_softmax=false


### path to save the model
model=/n/sd8/inaguma/result/csj

### path to the model directory to resume training
resume=

### path to save preproecssed data
export data=/n/sd8/inaguma/corpus/csj

### path to original data
CSJDATATOP=/n/rd25/mimura/corpus/CSJ  ## CSJ database top directory.
CSJVER=dvd  ## Set your CSJ format (dvd or usb).
## Usage    :
## Case DVD : We assume CSJ DVDs are copied in this directory with the names dvd1, dvd2,...,dvd17.
##            Neccesary directory is dvd3 - dvd17.
##            e.g. $ ls ${CSJDATATOP}(DVD) => 00README.txt dvd1 dvd2 ... dvd17
##
## Case USB : Neccesary directory is MORPH/SDB and WAV
##            e.g. $ ls ${CSJDATATOP}(USB) => 00README.txt DOC MORPH ... WAV fileList.csv
## Case merl :MERL setup. Neccesary directory is WAV and sdb

### data size
data_size=all
# NOTE: aps_other=default using "Academic lecture" and "other" data,
#       aps=using "Academic lecture" data,
#       sps=using "Academic lecture" data,
#       all_except_dialog=using All data except for "dialog" data,
#       all=using All data

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

set -e
set -u
set -o pipefail

if [ -z ${gpu} ]; then
    echo "Error: set GPU number." 1>&2
    echo "Usage: ./run.sh --gpu 0" 1>&2
    exit 1
fi
n_gpus=$(echo ${gpu} | tr "," "\n" | wc -l)

train_set=train_${data_size}
dev_set=dev_${data_size}
test_set="eval1 eval2 eval3"

# main
if [ ${unit} = char ]; then
    vocab_size=
fi
if [ ${unit} != wp ]; then
    wp_type=
fi
# sub1
if [ ${unit_sub1} = char ]; then
    vocab_size_sub1=
fi
if [ ${unit_sub1} != wp ]; then
    wp_type_sub1=
fi
# sub2
if [ ${unit_sub2} = char ]; then
    vocab_size_sub2=
fi
if [ ${unit_sub2} != wp ]; then
    wp_type_sub2=
fi

if [ ${stage} -le 0 ] && [ ! -e ${data}/.done_stage_0_${data_size} ]; then
    echo ============================================================================
    echo "                       Data Preparation (stage:0)                          "
    echo ============================================================================

    mkdir -p ${data}
    local/csj_make_trans/csj_autorun.sh ${CSJDATATOP} ${data}/csj-data ${CSJVER} || exit 1;
    local/csj_data_prep.sh ${data}/csj-data ${data_size} || exit 1;
    for x in eval1 eval2 eval3; do
        local/csj_eval_data_prep.sh ${data}/csj-data/eval ${x} || exit 1;
    done

    # Remove <sp> and POS tag, and lowercase
    for x in ${train_set} ${test_set}; do
        local/remove_pos.py ${data}/${x}/text | nkf -Z > ${data}/${x}/text.tmp
        mv ${data}/${x}/text.tmp ${data}/${x}/text
    done

    touch ${data}/.done_stage_0_${data_size} && echo "Finish data preparation (stage: 0)."
fi

if [ ${stage} -le 1 ] && [ ! -e ${data}/.done_stage_1_${data_size} ]; then
    echo ============================================================================
    echo "                    Feature extranction (stage:1)                          "
    echo ============================================================================

    for x in ${train_set} ${test_set}; do
        steps/make_fbank.sh --nj 32 --cmd "$train_cmd" --write_utt2num_frames true \
            ${data}/${x} ${data}/log/make_fbank/${x} ${data}/fbank || exit 1;
    done

    # Use the first 4k sentences from training data as dev set. (39 speakers.)
    utils/subset_data_dir.sh --first ${data}/${train_set} 4000 ${data}/${dev_set} || exit 1;  # 6hr 31min
    n=$[$(cat ${data}/${train_set}/segments | wc -l) - 4000]
    utils/subset_data_dir.sh --last ${data}/${train_set} ${n} ${data}/${train_set}.tmp || exit 1;

    # Finally, the full training set:
    utils/data/remove_dup_utts.sh 300 ${data}/${train_set}.tmp ${data}/${train_set} || exit 1;  # 233hr 36min
    rm -rf ${data}/*.tmp

    # Compute global CMVN
    compute-cmvn-stats scp:${data}/${train_set}/feats.scp ${data}/${train_set}/cmvn.ark || exit 1;

    # Apply global CMVN & dump features
    dump_feat.sh --cmd "$train_cmd" --nj 400 \
        ${data}/${train_set}/feats.scp ${data}/${train_set}/cmvn.ark ${data}/log/dump_feat/${train_set} ${data}/dump/${train_set} || exit 1;
    dump_feat.sh --cmd "$train_cmd" --nj 32 \
        ${data}/${dev_set}/feats.scp ${data}/${train_set}/cmvn.ark ${data}/log/dump_feat/${dev_set} ${data}/dump/${dev_set} || exit 1;
    for x in ${test_set}; do
        dump_dir=${data}/dump/${x}_${data_size}
        dump_feat.sh --cmd "$train_cmd" --nj 32 \
            ${data}/${x}/feats.scp ${data}/${train_set}/cmvn.ark ${data}/log/dump_feat/${x}_${data_size} ${dump_dir} || exit 1;
    done

    touch ${data}/.done_stage_1_${data_size} && echo "Finish feature extranction (stage: 1)."
fi

# main
dict=${data}/dict/${train_set}_${unit}${wp_type}${vocab_size}.txt; mkdir -p ${data}/dict
wp_model=${data}/dict/${train_set}_${wp_type}${vocab_size}
if [ ${stage} -le 2 ] && [ ! -e ${data}/.done_stage_2_${data_size}_${unit}${wp_type}${vocab_size} ]; then
    echo ============================================================================
    echo "                      Dataset preparation (stage:2, main)                  "
    echo ============================================================================

    echo "Making a dictionary..."
    echo "<unk> 1" > ${dict}  # <unk> must be 1, 0 will be used for "blank" in CTC
    echo "<eos> 2" >> ${dict}  # <sos> and <eos> share the same index
    echo "<pad> 3" >> ${dict}
    [ ${unit} = char ] && echo "<space> 4" >> ${dict}
    offset=$(cat ${dict} | wc -l)
    if [ ${unit} = wp ]; then
        cut -f 2- -d " " ${data}/${train_set}/text > ${data}/dict/input.txt
        spm_train --input=${data}/dict/input.txt --vocab_size=${vocab_size} \
            --model_type=${wp_type} --model_prefix=${wp_model} --input_sentence_size=100000000 --character_coverage=1.0
        spm_encode --model=${wp_model}.model --output_format=piece < ${data}/dict/input.txt | tr ' ' '\n' | \
            sort | uniq -c | sort -n -k1 -r | sed -e 's/^[ ]*//g' | awk -v offset=${offset} '{print $2 " " NR+offset}' >> ${dict}
        # NOTE: sort by frequency
    else
        text2dict.py ${data}/${train_set}/text --unit ${unit} --vocab_size ${vocab_size} | \
            awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict} || exit 1;
    fi
    echo "vocab size:" $(cat ${dict} | wc -l)

    # Compute OOV rate
    if [ ${unit} = word ]; then
        mkdir -p ${data}/dict/word_count ${data}/dict/oov_rate
        echo "OOV rate:" > ${data}/dict/oov_rate/word${vocab_size}_${data_size}.txt
        for x in ${train_set} ${dev_set} ${test_set}; do
            cut -f 2- -d " " ${data}/${x}/text | tr " " "\n" | sort | uniq -c | sort -n -k1 -r \
                > ${data}/dict/word_count/${x}_${data_size}.txt || exit 1;
            compute_oov_rate.py ${data}/dict/word_count/${x}_${data_size}.txt ${dict} ${x} \
                >> ${data}/dict/oov_rate/word${vocab_size}_${data_size}.txt || exit 1;
        done
        cat ${data}/dict/oov_rate/word${vocab_size}_${data_size}.txt
    fi

    echo "Making dataset tsv files for ASR ..."
    mkdir -p ${data}/dataset
    make_dataset.sh --feat ${data}/dump/${train_set}/feats.scp --unit ${unit} --wp_model ${wp_model} \
        ${data}/${train_set} ${dict} > ${data}/dataset/${train_set}_${unit}${wp_type}${vocab_size}.tsv || exit 1;
    make_dataset.sh --feat ${data}/dump/${dev_set}/feats.scp --unit ${unit} --wp_model ${wp_model} \
        ${data}/${dev_set} ${dict} > ${data}/dataset/${dev_set}_${unit}${wp_type}${vocab_size}.tsv || exit 1;
    for x in ${test_set}; do
        dump_dir=${data}/dump/${x}_${data_size}
        make_dataset.sh --feat ${dump_dir}/feats.scp --unit ${unit} --wp_model ${wp_model} \
            ${data}/${x} ${dict} > ${data}/dataset/${x}_${data_size}_${unit}${wp_type}${vocab_size}.tsv || exit 1;
    done

    touch ${data}/.done_stage_2_${data_size}_${unit}${wp_type}${vocab_size} && echo "Finish creating dataset for ASR (stage: 2)."
fi

# sub1
dict_sub1=${data}/dict/${train_set}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1}.txt
wp_model_sub1=${data}/dict/${train_set}_${wp_type_sub1}${vocab_size_sub1}
if [ ${stage} -le 2 ] && [ ! -e ${data}/.done_stage_2_${data_size}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1} ]; then
    echo ============================================================================
    echo "                      Dataset preparation (stage:2, sub1)                  "
    echo ============================================================================

    echo "Making a dictionary..."
    echo "<unk> 1" > ${dict_sub1}  # <unk> must be 1, 0 will be used for "blank" in CTC
    echo "<eos> 2" >> ${dict_sub1}  # <sos> and <eos> share the same index
    echo "<pad> 3" >> ${dict_sub1}
    [ ${unit_sub1} = char ] && echo "<space> 4" >> ${dict_sub1}
    offset=$(cat ${dict_sub1} | wc -l)
    if [ ${unit_sub1} = wp ]; then
        cut -f 2- -d " " ${data}/${train_set}/text > ${data}/dict/input.txt
        spm_train --input=${data}/dict/input.txt --vocab_size=${vocab_size_sub1} \
            --model_type=${wp_type_sub1} --model_prefix=${wp_model_sub1} --input_sentence_size=100000000 --character_coverage=1.0
        spm_encode --model=${wp_model_sub1}.model --output_format=piece < ${data}/dict/input.txt | tr ' ' '\n' | \
            sort | uniq -c | sort -n -k1 -r | sed -e 's/^[ ]*//g' | awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict_sub1}
        # NOTE: sort by frequency
    else
        text2dict.py ${data}/${train_set}/text --unit ${unit_sub1} --vocab_size ${vocab_size_sub1} | \
            awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict_sub1} || exit 1;
    fi
    echo "vocab size:" $(cat ${dict_sub1} | wc -l)

    echo "Making dataset tsv files for ASR ..."
    make_dataset.sh --feat ${data}/dump/${train_set}/feats.scp --unit ${unit_sub1} --wp_model ${wp_model_sub1} \
        ${data}/${train_set} ${dict_sub1} > ${data}/dataset/${train_set}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1}.tsv || exit 1;
    make_dataset.sh --feat ${data}/dump/${dev_set}/feats.scp --unit ${unit_sub1} --wp_model ${wp_model_sub1} \
        ${data}/${dev_set} ${dict_sub1} > ${data}/dataset/${dev_set}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1}.tsv || exit 1;
    for x in ${test_set}; do
        dump_dir=${data}/dump/${x}_${data_size}
        make_dataset.sh --feat ${dump_dir}/feats.scp --unit ${unit_sub1} --wp_model ${wp_model_sub1} \
            ${data}/${x} ${dict_sub1} > ${data}/dataset/${x}_${data_size}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1}.tsv || exit 1;
    done

    touch ${data}/.done_stage_2_${data_size}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1} && echo "Finish creating dataset for ASR (stage: 2)."
fi

# sub2
dict_sub2=${data}/dict/${train_set}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2}.txt
wp_model_sub2=${data}/dict/${train_set}_${wp_type_sub2}${vocab_size_sub2}
if [ ${stage} -le 2 ] && [ ! -e ${data}/.done_stage_2_${data_size}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2} ]; then
    echo ============================================================================
    echo "                      Dataset preparation (stage:2, sub2)                  "
    echo ============================================================================

    echo "Making a dictionary..."
    echo "<unk> 1" > ${dict_sub2}  # <unk> must be 1, 0 will be used for "blank" in CTC
    echo "<eos> 2" >> ${dict_sub2}  # <sos> and <eos> share the same index
    echo "<pad> 3" >> ${dict_sub2}
    [ ${unit_sub2} = char ] && echo "<space> 4" >> ${dict_sub2}
    offset=$(cat ${dict_sub2} | wc -l)
    if [ ${unit_sub2} = wp ]; then
        cut -f 2- -d " " ${data}/${train_set}/text > ${data}/dict/input.txt
        spm_train --input=${data}/dict/input.txt --vocab_size=${vocab_size_sub2} \
            --model_type=${wp_type_sub2} --model_prefix=${wp_model_sub2} --input_sentence_size=100000000 --character_coverage=1.0
        spm_encode --model=${wp_model_sub2}.model --output_format=piece < ${data}/dict/input.txt | tr ' ' '\n' | \
            sort | uniq -c | sort -n -k1 -r | sed -e 's/^[ ]*//g' | awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict_sub2}
        # NOTE: sort by frequency
    else
        text2dict.py ${data}/${train_set}/text --unit ${unit_sub2} --vocab_size ${vocab_size_sub2} | \
            awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict_sub2} || exit 1;
    fi
    echo "vocab size:" $(cat ${dict_sub2} | wc -l)

    echo "Making dataset tsv files for ASR ..."
    make_dataset.sh --feat {data}/dump/${train_set}/feats.scp --unit ${unit_sub1} --wp_model ${wp_model_sub2} \
        ${data}/${train_set} ${dict_sub2} > ${data}/dataset/${train_set}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2}.tsv || exit 1;
    make_dataset.sh --feat {data}/dump/${dev_set}/feats.scp --unit ${unit_sub2} --wp_model ${wp_model_sub2} \
        ${data}/${dev_set} ${dict_sub2} > ${data}/dataset/${dev_set}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2}.tsv || exit 1;
    for x in ${test_set}; do
        dump_dir=${data}/dump/${x}_${data_size}
        make_dataset.sh --feat ${dump_dir}/feats.scp --unit ${unit_sub2} --wp_model ${wp_model_sub2} \
            ${data}/${x} ${dict_sub2} > ${data}/dataset/${x}_${data_size}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2}.tsv || exit 1;
    done

    touch ${data}/.done_stage_2_${data_size}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2} && echo "Finish creating dataset for ASR (stage: 2)."
fi

mkdir -p ${model}
if [ ${stage} -le 4 ]; then
    echo ============================================================================
    echo "                       ASR Training stage (stage:4)                        "
    echo ============================================================================

    CUDA_VISIBLE_DEVICES=${gpu} ${NEURALSP_ROOT}/neural_sp/bin/asr/train.py \
        --corpus csj \
        --n_gpus ${n_gpus} \
        --train_set ${data}/dataset/${train_set}_${unit}${wp_type}${vocab_size}.tsv \
        --train_set_sub1 ${data}/dataset/${train_set}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1}.tsv \
        --train_set_sub2 ${data}/dataset/${train_set}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2}.tsv \
        --dev_set ${data}/dataset/${dev_set}_${unit}${wp_type}${vocab_size}.tsv \
        --dev_set_sub1 ${data}/dataset/${dev_set}_${unit_sub1}${wp_type_sub1}${vocab_size_sub1}.tsv \
        --dev_set_sub2 ${data}/dataset/${dev_set}_${unit_sub2}${wp_type_sub2}${vocab_size_sub2}.tsv \
        --eval_sets ${data}/dataset/eval1_${data_size}_${unit}${wp_type}${vocab_size}.tsv \
        --dict ${dict} \
        --dict_sub1 ${dict_sub1} \
        --dict_sub2 ${dict_sub2} \
        --wp_model ${wp_model}.model \
        --wp_model_sub1 ${wp_model_sub1}.model \
        --wp_model_sub2 ${wp_model_sub2}.model \
        --model ${model}/asr \
        --unit ${unit} \
        --unit_sub1 ${unit_sub1} \
        --unit_sub2 ${unit_sub2} \
        --n_splices ${n_splices} \
        --n_stacks ${n_stacks} \
        --n_skips ${n_skips} \
        --conv_in_channel ${conv_in_channel} \
        --conv_channels ${conv_channels} \
        --conv_kernel_sizes ${conv_kernel_sizes} \
        --conv_strides ${conv_strides} \
        --conv_poolings ${conv_poolings} \
        --conv_batch_norm ${conv_batch_norm} \
        --conv_bottleneck_dim ${conv_bottleneck_dim} \
        --enc_type ${enc_type} \
        --enc_n_units ${enc_n_units} \
        --enc_n_projs ${enc_n_projs} \
        --enc_n_layers ${enc_n_layers} \
        --enc_n_layers_sub1 ${enc_n_layers_sub1} \
        --enc_n_layers_sub2 ${enc_n_layers_sub2} \
        --enc_residual ${enc_residual} \
        --subsample ${subsample} \
        --subsample_type ${subsample_type} \
        --attn_type ${attn_type} \
        --attn_dim ${attn_dim} \
        --attn_n_heads ${attn_n_heads} \
        --attn_sigmoid ${attn_sigmoid} \
        --dec_type ${dec_type} \
        --dec_n_units ${dec_n_units} \
        --dec_n_projs ${dec_n_projs} \
        --dec_n_layers ${dec_n_layers} \
        --dec_loop_type ${dec_loop_type} \
        --dec_residual ${dec_residual} \
        --input_feeding ${input_feeding} \
        --dec_bottleneck_dim ${dec_bottleneck_dim} \
        --emb_dim ${emb_dim} \
        --tie_embedding ${tie_embedding} \
        --ctc_fc_list ${ctc_fc_list} \
        --ctc_fc_list_sub1 ${ctc_fc_list_sub1} \
        --ctc_fc_list_sub2 ${ctc_fc_list_sub2} \
        --batch_size ${batch_size} \
        --optimizer ${optimizer} \
        --learning_rate ${learning_rate} \
        --n_epochs ${n_epochs} \
        --convert_to_sgd_epoch ${convert_to_sgd_epoch} \
        --print_step ${print_step} \
        --decay_start_epoch ${decay_start_epoch} \
        --decay_rate ${decay_rate} \
        --decay_type ${decay_type} \
        --decay_patient_n_epochs ${decay_patient_n_epochs} \
        --not_improved_patient_n_epochs ${not_improved_patient_n_epochs} \
        --eval_start_epoch ${eval_start_epoch} \
        --warmup_start_learning_rate ${warmup_start_learning_rate} \
        --warmup_n_steps ${warmup_n_steps} \
        --param_init ${param_init} \
        --param_init_dist ${param_init_dist} \
        --pretrained_model ${pretrained_model} \
        --clip_grad_norm ${clip_grad_norm} \
        --dropout_in ${dropout_in} \
        --dropout_enc ${dropout_enc} \
        --dropout_dec ${dropout_dec} \
        --dropout_emb ${dropout_emb} \
        --dropout_att ${dropout_att} \
        --weight_decay ${weight_decay} \
        --ss_prob ${ss_prob} \
        --ss_type ${ss_type} \
        --lsm_prob ${lsm_prob} \
        --layer_norm ${layer_norm} \
        --focal_loss_weight ${focal_loss} \
        --adaptive_softmax ${adaptive_softmax} \
        --ctc_weight ${ctc_weight} \
        --ctc_weight_sub1 ${ctc_weight_sub1} \
        --ctc_weight_sub2 ${ctc_weight_sub2} \
        --bwd_weight ${bwd_weight} \
        --sub1_weight ${sub1_weight} \
        --sub2_weight ${sub2_weight} \
        --mtl_per_batch ${mtl_per_batch} \
        --task_specific_layer ${task_specific_layer} \
        --lm_fusion_type ${lm_fusion_type} \
        --lm_fusion ${lm_fusion} \
        --lm_init ${lm_init} \
        --lmobj_weight ${lmobj_weight} \
        --share_lm_softmax ${share_lm_softmax} \
        --resume ${resume} || exit 1;

    echo "Finish model training (stage: 4)."
fi
