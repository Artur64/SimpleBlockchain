defmodule Blockchain.Keys.Key do
  @default_entropy_size 16

  @spec create_private_key() :: binary()
  def create_private_key() do
    :crypto.strong_rand_bytes(@default_entropy_size)
  end

  @spec get_public_key(binary()) :: binary()
  def get_public_key(private_key) do
    {pub_key, _priv_key} = :crypto.generate_key(:ecdh, :secp256k1, private_key)
    pub_key
  end
  @spec get_keypair() :: binary()
  def get_keypair() do
    #TODO implement random keypair generation
  end
end
