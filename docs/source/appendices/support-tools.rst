.. _support-tools:

*************
Support Tools
*************

This appendix outlines the set of support tools provided with
GYRE. These executable tools are built by default during compilation,
and can be found in the :file:`${GYRE_DIR}/bin` directory.


Evaluating Coefficients
-----------------------

The following tools evaluate oscillation- or tide-related coefficients
for a given stellar model and/or set of parameters:

.. toctree::
   :maxdepth: 2

   support-tools/eval-lambda.rst
   support-tools/eval-love.rst
   support-tools/eval-tidal-coeff.rst

Manipulating Models
-------------------

The following tools create or convert models in the various
:ref:`stellar-models` types supported by GYRE:

.. toctree::
   :maxdepth: 2

   support-tools/build-poly.rst
   support-tools/poly-to-fgong.rst
   support-tools/poly-to-txt.rst
