#! /usr/bin/env python
# -*- coding: utf-8 -*-

"""Load each encoder."""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

from models.pytorch.encoders.rnn import RNNEncoder
from models.pytorch.encoders.pyramid_rnn import PyramidRNNEnocer
# from models.pytorch.encoders.vgg import VGGEncoder
# from models.pytorch.encoders.resnet import ResNetEncoder


ENCODERS = {
    "lstm": RNNEncoder,
    "gru": RNNEncoder,
    "rnn": RNNEncoder,
    "plstm": PyramidRNNEnocer,
    "pgru": PyramidRNNEnocer,
    "prnn": PyramidRNNEnocer,
    # "vgg": VGGEncoder,
    # "resnet": ResNetEncoder,
}


def load(encoder_type):
    """Load an encoder.
    Args:
        encoder_type (string): name of the encoder in the key of ENCODERS
    Returns:
        model (nn.Module): An encoder class
    """
    if encoder_type not in ENCODERS:
        raise TypeError(
            "encoder_type should be one of [%s], you provided %s." %
            (", ".join(ENCODERS), encoder_type))
    return ENCODERS[encoder_type]
