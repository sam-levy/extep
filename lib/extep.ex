defmodule Extep do
  defstruct status: :ok, context: %{}, last_step: nil, last_step_idx: nil

  @tag_status_dict %{ok: :ok, halt: :halted, error: :error}

  @type status :: :ok | :halted | :error

  @type context :: map()

  @type t :: %Extep{
          status: status(),
          context: context(),
          last_step: atom(),
          last_step_idx: nil | non_neg_integer()
        }

  @type ctx_key :: atom() | non_neg_integer() | {atom(), non_neg_integer()}

  @type return_tag :: :ok | :halt | :error
  @type return_type :: return_tag() | {return_tag(), any()}
  @type ctx_mod_fun :: (context() -> return_type())

  defguardp is_halted(status) when status in [:halted, :error]

  defguardp is_ctx_key(key) when is_atom(key) or is_integer(key) or is_tuple(key)

  defguardp is_valid_return_tag(tag) when tag in [:ok, :halt, :error]

  @spec new :: t()
  def new, do: %Extep{}

  @spec new(map()) :: t()
  def new(context) when is_map(context), do: %Extep{context: context}

  @spec run(t(), ctx_mod_fun()) :: t()
  def run(%Extep{status: :ok, last_step_idx: nil} = extep, fun), do: run(extep, 0, fun)
  def run(%Extep{status: :ok} = extep, fun), do: run(extep, extep.last_step_idx + 1, fun)
  def run(%Extep{status: status} = extep, _fun) when is_halted(status), do: extep

  @spec run(t(), ctx_key(), ctx_mod_fun()) :: t()
  def run(%Extep{status: :ok, context: context} = extep, ctx_key, fun) do
    context
    |> fun.()
    |> update_extep(extep, ctx_key)
  end

  def run(%Extep{status: status} = extep, _ctx_key, _fun) when is_halted(status), do: extep

  @spec return(t()) :: return_type()
  def return(%Extep{} = extep), do: handle_return(extep, extep.last_step)

  @spec return(t(), ctx_key()) :: return_type()
  def return(%Extep{status: :ok} = extep, ctx_key) when is_ctx_key(ctx_key) do
    handle_return(extep, ctx_key)
  end

  @spec return(t(), ctx_mod_fun()) :: return_type()
  def return(%Extep{status: :ok} = extep, fun) when is_function(fun, 1) do
    return(extep, extep.last_step_idx + 1, fun)
  end

  def return(%Extep{status: status} = extep, _ctx_key_or_fun) when is_halted(status) do
    handle_return(extep, extep.last_step)
  end

  @spec return(t(), ctx_key(), ctx_mod_fun()) :: return_type()
  def return(%Extep{status: :ok} = extep, ctx_key, fun) do
    extep
    |> run(ctx_key, fun)
    |> handle_return(ctx_key)
  end

  def return(%Extep{status: status} = extep, _ctx_key, _fun) when is_halted(status) do
    handle_return(extep, extep.last_step)
  end

  @spec update_extep({return_tag(), any()}, t(), ctx_key()) :: t()
  defp update_extep({tag, value}, %Extep{} = extep, ctx_key) when is_valid_return_tag(tag) do
    Map.merge(extep, %{
      status: Map.get(@tag_status_dict, tag),
      context: Map.put(extep.context, ctx_key, value),
      last_step: ctx_key,
      last_step_idx: handle_idx(extep.last_step_idx)
    })
  end

  @spec update_extep(return_tag(), t(), ctx_key()) :: t()
  defp update_extep(tag, %Extep{} = extep, ctx_key) when is_valid_return_tag(tag) do
    update_extep({tag, tag}, extep, ctx_key)
  end

  defp update_extep(_tag, _extep, _ctx_key), do: raise(Extep.InvalidFunctionReturn)

  @spec handle_return(t(), ctx_key()) :: return_type()
  defp handle_return(%Extep{status: status, context: context}, ctx_key) do
    case Map.get(context, ctx_key) do
      :ok -> :ok
      :halt -> :ok
      :error -> :error
      step_return when status in [:ok, :halted] -> {:ok, step_return}
      step_return when status == :error -> {:error, step_return}
    end
  end

  defp handle_idx(nil), do: 0
  defp handle_idx(idx), do: idx + 1
end

# TODO:
#   [ ] Add `:to` option
#   [ ] Add `:label_error` option
#   [ ] Add `:async?` option
