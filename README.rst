.. default-role:: code


Pim
===

Pig + Vim = Pim.


Features
--------

Pim provides a simple way to describe any variable in a pig script and load 
parts of your script in grunt directly from Vim. Its most powerful feature is 
remote execution support, e.g. when pig can only be run from a gateway machine:
Pim will handle the underlying connections and transfers such that it's as 
simple as if pig was running locally. Pim also caches and multiplexes 
connections to speed up remote calls.

Note that Pim currently only support Kerberos gateway authentication. Run 
`:help Pim` from inside Vim to learn more.


Installation
------------

With `pathogen.vim`_:

.. code:: bash

  $ cd ~/.vim/bundle
  $ git clone https://github.com/mtth/pim.vim

Otherwise simply copy the folders into your ``.vim`` directory.


Other
-----

For syntax highlighting in your `.pig` files, we recommend pig.vim_.


.. _pathogen.vim: https://github.com/tpope/vim-pathogen
.. _pig.vim: https://github.com/motus/pig.vim
