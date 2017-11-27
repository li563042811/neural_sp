#! /usr/bin/env python
# -*- coding: utf-8 -*-

"""Test praimidal RNN encoders in pytorch."""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import sys
import unittest
import numpy as np

sys.path.append('../../../')
from models.pytorch.encoders.load_encoder import load
from models.test.data import generate_data
from utils.io.variable import np2var, var2np
from utils.measure_time_func import measure_time


class TestPyramidRNNEncoders(unittest.TestCase):

    def test(self):
        print("Pyramidal RNN Encoders Working check.")

        # LSTM
        self.check(encoder_type='lstm', bidirectional=False,
                   subsample_type='drop')
        self.check(encoder_type='lstm', bidirectional=True,
                   subsample_type='drop')
        self.check(encoder_type='lstm', bidirectional=True,
                   batch_first=True, subsample_type='drop')
        self.check(encoder_type='lstm', bidirectional=False,
                   subsample_type='concat')
        self.check(encoder_type='lstm', bidirectional=True,
                   subsample_type='concat')
        self.check(encoder_type='lstm', bidirectional=True,
                   batch_first=True, subsample_type='concat')
        self.check(encoder_type='lstm', bidirectional=True,
                   merge_bidirectional=True)

        # GRU
        self.check(encoder_type='gru', bidirectional=False,
                   subsample_type='drop')
        self.check(encoder_type='gru', bidirectional=True,
                   subsample_type='drop')
        self.check(encoder_type='gru', bidirectional=True,
                   batch_first=True, subsample_type='drop')
        self.check(encoder_type='gru', bidirectional=False,
                   subsample_type='concat')
        self.check(encoder_type='gru', bidirectional=True,
                   subsample_type='concat')
        self.check(encoder_type='gru', bidirectional=True,
                   batch_first=True, subsample_type='concat')
        self.check(encoder_type='gru', bidirectional=True,
                   merge_bidirectional=True)

        # RNN
        self.check(encoder_type='rnn', bidirectional=False,
                   subsample_type='drop')
        self.check(encoder_type='rnn', bidirectional=True,
                   subsample_type='drop')
        self.check(encoder_type='rnn', bidirectional=True,
                   batch_first=True, subsample_type='drop')
        self.check(encoder_type='rnn', bidirectional=False,
                   subsample_type='concat')
        self.check(encoder_type='rnn', bidirectional=True,
                   subsample_type='concat')
        self.check(encoder_type='rnn', bidirectional=True,
                   batch_first=True, subsample_type='concat')
        self.check(encoder_type='rnn', bidirectional=True,
                   merge_bidirectional=True)

    @measure_time
    def check(self, encoder_type, bidirectional=False, batch_first=False,
              subsample_type='concat', mask_sequence=True,
              merge_bidirectional=False):

        print('==================================================')
        print('  encoder_type: %s' % encoder_type)
        print('  bidirectional: %s' % str(bidirectional))
        print('  batch_first: %s' % str(batch_first))
        print('  subsample_type: %s' % subsample_type)
        print('  mask_sequence: %s' % str(mask_sequence))
        print('  merge_bidirectional: %s' % str(merge_bidirectional))
        print('==================================================')

        # Load batch data
        batch_size = 4
        inputs, _, inputs_seq_len, _ = generate_data(
            model_type='ctc',
            batch_size=batch_size,
            splice=1)

        # Wrap by Variable
        inputs = np2var(inputs)
        inputs_seq_len = np2var(inputs_seq_len)

        max_time = inputs.size(1)

        # Load encoder
        encoder = load(encoder_type='p' + encoder_type + '_hierarchical')

        # Initialize encoder
        if encoder_type in ['lstm', 'gru', 'rnn']:
            encoder = encoder(
                input_size=inputs.size(-1),
                rnn_type=encoder_type,
                bidirectional=bidirectional,
                num_units=256,
                num_proj=0,
                num_layers=6,
                num_layers_sub=4,
                dropout=0.2,
                parameter_init=0.1,
                subsample_list=[False, True, True, False, False, False],
                subsample_type=subsample_type,
                batch_first=batch_first)
        else:
            raise NotImplementedError

        outputs, final_state, outputs_sub, final_state_sub, perm_indices = encoder(
            inputs, inputs_seq_len, mask_sequence=mask_sequence)
        max_time_sub = max_time / \
            (2 ** sum(encoder.subsample_list[:encoder.num_layers_sub]))
        max_time_sub = int(max_time_sub)
        max_time /= (2 ** sum(encoder.subsample_list))
        max_time = int(max_time)

        # Check final state (forward)
        if not merge_bidirectional:
            print('----- Check hidden states (forward) -----')
            if batch_first:
                outputs_fw_final = outputs.transpose(
                    0, 1)[-1, 0, :encoder.num_units]
                outputs_sub_fw_final = outputs_sub.transpose(
                    0, 1)[-1, 0, :encoder.num_units]
            else:
                outputs_fw_final = outputs[-1, 0, :encoder.num_units]
                outputs_sub_fw_final = outputs_sub[-1, 0, :encoder.num_units]
            assert np.all(var2np(outputs_fw_final) ==
                          var2np(final_state[0, 0, :]))
            assert np.all(var2np(outputs_sub_fw_final) ==
                          var2np(final_state_sub[0, 0, :]))

        print('----- final state -----')
        print(final_state_sub.size())
        print(final_state.size())
        self.assertEqual((1, batch_size, encoder.num_units),
                         final_state_sub.size())
        self.assertEqual((1, batch_size, encoder.num_units),
                         final_state.size())

        print('----- outputs -----')
        print(inputs.size())
        print(outputs_sub.size())
        print(outputs.size())
        num_directions = 2 if bidirectional and not merge_bidirectional else 1
        if batch_first:
            self.assertEqual((batch_size, max_time_sub, encoder.num_units * num_directions),
                             outputs_sub.size())
            self.assertEqual((batch_size, max_time, encoder.num_units * num_directions),
                             outputs.size())
        else:
            self.assertEqual((max_time_sub, batch_size, encoder.num_units * num_directions),
                             outputs_sub.size())
            self.assertEqual((max_time, batch_size, encoder.num_units * num_directions),
                             outputs.size())


if __name__ == '__main__':
    unittest.main()
