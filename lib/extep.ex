defmodule Extep do
  @moduledoc """
  A tiny and friendly step runner for Elixir pipelines.

  Extep is a simple and dependency-free utility that helps you compose Elixir pipelines using a shared context.
  It's useful for building multi-step workflows that can gracefully **halt** or **error** along the way.
  Extep is an implementation of the Railway-oriented programming and was inspired by
  [Ecto.Multi](https://hexdocs.pm/ecto/Ecto.Multi.html) and [Sage](https://hexdocs.pm/sage/readme.html).

  ## Example

      iex> params = %{user_id: 1, plan: "super-power-plus"}
      iex> Extep.new(%{params: params})
      ...> |> Extep.run(:params, &validate_params/1)
      ...> |> Extep.async(:user, &fetch_user/1)
      ...> |> Extep.async(:items, &fetch_items/1)
      ...> |> Extep.return(&create_subscription/1, label_error: true)
      {:ok, %{id: 123, object: "subscription", user_id: 1, items: [%{code: "item1"}, %{code: "item2"}]}}
  """
  use Application

  alias __MODULE__

  defstruct status: :ok, context: %{}, tasks: [], message: nil

  @type status :: :ok | :halted | :error
  @type context :: map()
  @type tasks :: list(Task.t())
  @type t :: %__MODULE__{
          status: status(),
          context: context(),
          tasks: tasks(),
          message: any()
        }

  defguardp is_ok(extep)
            when is_struct(extep, __MODULE__) and extep.status == :ok

  defguardp is_interrupted(extep)
            when is_struct(extep, __MODULE__) and extep.status in [:halted, :error]

  @type context_key :: atom()
  @type context_checker_fun ::
          (context() ->
             :ok | {:ok, any()} | {:halt, any()} | {:error, any()})
  @type context_mutator_fun :: (context() -> {:ok, any()} | {:halt, any()} | {:error, any()})

  defguardp is_ctx_fun(fun) when is_function(fun, 1)

  @type opts :: keyword()

  @doc false
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      {Task.Supervisor, name: Extep.AsyncStepSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Extep.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Creates a new `Extep` struct with an empty context.

  ## Examples

      iex> Extep.new()
      %Extep{status: :ok, context: %{}, message: nil}
  """
  @spec new :: t()
  def new do
    %Extep{}
  end

  @doc """
  Creates a new `Extep` struct with an initial context map.

  ## Examples

      iex> Extep.new(%{foo: "bar"})
      %Extep{status: :ok, context: %{foo: "bar"}, message: nil}
  """
  @spec new(map()) :: t()
  def new(context) when is_map(context) do
    %Extep{context: context}
  end

  @doc """
  Asynchronously runs a checker function on the context without modifying it.

  This is the async version of `run/2`. It starts a task to execute the checker function
  in parallel while the pipeline continues. The task result is processed when `await/2`
  is called. Like `run/2`, the context remains unchanged regardless of the function's
  return value.

  ## Function Return Values

  The async checker function must return the same values as `run/2`:

  - `:ok` - Pipeline continues with unchanged context
  - `{:ok, value}` - Pipeline continues with unchanged context (value is ignored)
  - `{:halt, reason}` - Pipeline stops with `:halted` status, reason stored in message
  - `{:error, reason}` - Pipeline stops with `:error` status, reason stored in message

  ## Examples

      iex> Extep.new(%{user_id: 1})
      ...> |> Extep.async(fn _ctx -> :ok end)
      ...> |> Extep.async(fn _ctx -> {:ok, "validated"} end)
      ...> |> Extep.await()
      %Extep{status: :ok, context: %{user_id: 1}, message: nil}

  See `run/2` for detailed behavior and error handling patterns.
  """
  @spec async(t(), context_checker_fun()) :: t()
  def async(extep, fun) when is_ok(extep) and is_ctx_fun(fun) do
    put_task([extep, fun])
  end

  def async(extep, fun) when is_interrupted(extep) and is_ctx_fun(fun), do: extep

  @doc """
  Asynchronously runs a mutator function that updates the context under the given key.

  This is the async version of `run/3`. It starts a task to execute the mutator function
  in parallel while the pipeline continues. The task result is processed when `await/2`
  is called, and the context will be updated with the result under the specified key.

  ## Function Return Values

  The async mutator function must return the same values as `run/3`:

  - `{:ok, value}` - Pipeline continues, `value` is stored under `context_key`
  - `{:halt, reason}` - Pipeline stops with `:halted` status, reason stored in message
  - `{:error, reason}` - Pipeline stops with `:error` status, reason stored in message

  ## Examples

      iex> Extep.new(%{user_id: 1})
      ...> |> Extep.async(:user, fn ctx -> {:ok, %{id: ctx.user_id, name: "Alice"}} end)
      ...> |> Extep.async(:items, fn _ctx -> {:ok, [%{code: "item1"}]} end)
      ...> |> Extep.await()
      %Extep{status: :ok, context: %{user_id: 1, user: %{id: 1, name: "Alice"}, items: [%{code: "item1"}]}, message: nil}

  See `run/3` for detailed behavior and error handling patterns.
  """
  @spec async(t(), context_key(), context_mutator_fun()) :: t()
  def async(extep, ctx_key, fun)
      when is_ok(extep) and is_atom(ctx_key) and is_ctx_fun(fun) do
    put_task([extep, ctx_key, fun])
  end

  def async(extep, ctx_key, fun)
      when is_interrupted(extep) and is_atom(ctx_key) and is_ctx_fun(fun) do
    extep
  end

  defp put_task([%Extep{} = extep | tail]) do
    args = [%{extep | tasks: []} | tail]
    task = Task.Supervisor.async_nolink(Extep.AsyncStepSupervisor, __MODULE__, :run, args)

    %{extep | tasks: [task | extep.tasks]}
  end

  @doc """
  Awaits completion of all pending async tasks and processes their results.

  This function waits for all tasks started by `async/2` and `async/3` to complete,
  then processes their results in the order they were started. If any task returns
  an error or halt, the pipeline stops and subsequent task results are ignored.

  ## Options

  * `:timeout` — how long to wait (in ms) for all tasks to reply.
    Defaults to `10_000`. You can also pass `:infinity`.

    This function uses `Task.await_many/2`. If the timeout elapses before all tasks reply, the caller **exits** with `{:timeout, {Task, :await_many, ...}}`.

  ## Behavior

  - If the extep has no pending tasks, returns the extep unchanged
  - If the extep status is already `:halted` or `:error`, shuts down all tasks and returns the extep
  - For `:ok` status, waits for all tasks and merges their context changes
  - Stops at the first task that returns an error or halt

  ## Examples

      iex> Extep.new(%{user_id: 1})
      ...> |> Extep.async(:user, fn ctx -> {:ok, %{id: ctx.user_id, name: "Alice"}} end)
      ...> |> Extep.async(:items, fn _ctx -> {:ok, [%{code: "item1"}]} end)
      ...> |> Extep.await(timeout: 10)
      %Extep{status: :ok, context: %{user_id: 1, user: %{id: 1, name: "Alice"}, items: [%{code: "item1"}]}, message: nil}

  Note: `await/2` is automatically called by `run/2`, `run/3`, and `return/2` when there are pending tasks.
  """
  @spec await(t(), keyword()) :: map()
  def await(tasks, opts \\ [])

  def await(%{tasks: [_ | _]} = extep, opts) when is_ok(extep) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    extep =
      extep.tasks
      |> Task.await_many(timeout)
      |> Enum.reverse()
      |> Enum.reduce_while(extep, fn
        x, acc when is_ok(x) ->
          {:cont, %{acc | context: Map.merge(acc.context, x.context)}}

        x, acc when is_interrupted(x) ->
          {:halt, %{x | context: Map.merge(acc.context, x.context)}}
      end)

    %{extep | tasks: []}
  end

  def await(extep, _opts) when is_interrupted(extep), do: shutdown_tasks(extep)

  def await(%Extep{tasks: []} = extep, _opts), do: extep

  defp shutdown_tasks(%Extep{tasks: [_ | _]} = extep) do
    Enum.each(extep.tasks, &Task.shutdown(&1, :brutal_kill))

    %{extep | tasks: []}
  end

  defp shutdown_tasks(%Extep{tasks: []} = extep), do: extep

  @doc """
  Runs a checker function on the context without modifying it.

  This function is useful for validation, checking conditions, or performing side effects
  without changing the pipeline context. The context remains unchanged regardless of the
  function's return value.

  ## Function Return Values

  The checker function must return one of these values:

  - `:ok` - Pipeline continues with unchanged context
  - `{:ok, value}` - Pipeline continues with unchanged context (value is ignored)
  - `{:halt, reason}` - Pipeline stops with `:halted` status, reason stored in message
  - `{:error, reason}` - Pipeline stops with `:error` status, reason stored in message

  ## Error Message Labeling

  When errors occur, the message is stored differently based on the function type:

  - **Named functions**: Error labeled with function name (e.g., `%{validate_user: "error"}`)
  - **Anonymous functions**: Error labeled with `:no_label` (e.g., `%{no_label: "error"}`)

  ## Examples

  ### Successful Validation - Simple OK
  Basic validation that passes without returning a value:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(fn _ctx -> :ok end)
      %Extep{status: :ok, context: %{foo: 1}, message: nil}

  ### Successful Validation - OK tuple
  Validation that passes and returns an ok tuple (value is ignored, context unchanged):

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(fn _ctx -> {:ok, "is valid"} end)
      %Extep{status: :ok, context: %{foo: 1}, message: nil}

  ### Error with Named Function
  When a named function returns an error tuple, the error is labeled with the function name:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(&return_error_tuple/1)
      %Extep{status: :error, context: %{foo: 1}, message: %{return_error_tuple: "error message"}}

  ### Error with Anonymous Function
  When an anonymous function returns an error tuple, the error is labeled with `:no_label`:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(fn _ctx -> {:error, "error message"} end)
      %Extep{status: :error, context: %{foo: 1}, message: %{no_label: "error message"}}

  ### Halt Example
  When a function returns a halt tuple, the pipeline stops and the halt reason is stored:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(fn _ctx -> {:halt, {:ok, "halt message"}} end)
      %Extep{status: :halted, context: %{foo: 1}, message: {:ok, "halt message"}}

  It's useful when you want to stop the pipeline and return a specific message, like a
  cancel tuple for an Oban job, for example:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(fn _ctx -> {:halt, {:cancel, "cancel message"}} end)
      ...> |> Extep.return(fn ctx -> {:ok, ctx.bar + 2} end)
      {:cancel, "cancel message"}

  ## Pipeline Behavior

  - If the Extep struct already has `:halted` or `:error` status, this function does nothing
  - Only processes when the current status is `:ok`
  - The context is never modified by this function
  """
  @spec run(t(), context_checker_fun()) :: t()
  def run(extep, fun)

  def run(%{tasks: [_ | _]} = extep, fun) when is_ok(extep) and is_ctx_fun(fun) do
    extep
    |> await()
    |> run(fun)
  end

  def run(extep, fun) when is_ok(extep) and is_ctx_fun(fun) do
    case apply(fun, [extep.context]) do
      :ok -> extep
      {:ok, _} -> extep
      return -> interrupt(extep, return, fun, nil)
    end
  end

  def run(extep, fun) when is_interrupted(extep) and is_ctx_fun(fun), do: shutdown_tasks(extep)

  @doc """
  Runs a mutator function that updates the context with the result under the given key.

  This function executes a mutator function and stores its result in the context under the
  specified key. Unlike `run/2`, this function is designed to modify the context by adding
  or updating values.

  ## Parameters

  - `extep` - The current Extep struct
  - `context_key` - An atom representing the key where the result will be stored
  - `fun` - A function that takes the context and returns a result

  ## Function Return Values

  The mutator function must return one of these values:

  - `{:ok, value}` - Pipeline continues, `value` is stored under `context_key`
  - `{:halt, reason}` - Pipeline stops with `:halted` status, reason stored in message
  - `{:error, reason}` - Pipeline stops with `:error` status, reason stored in message

  **Note**: Unlike `run/2`, this function does NOT accept plain `:ok` returns. It requires
  a tuple with a value to store in the context.

  ## Error Message Labeling

  When errors occur, the message is stored differently based on the function type:

  - **Named functions**: Error labeled with function name (e.g., `%{fetch_user: "error"}`)
  - **Anonymous functions**: Error labeled with the context key (e.g., `%{user: "error"}`)

  ## Examples

  ### Successful Context Updates
  This example shows how values are stored and can be used by subsequent steps:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:foo, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 2} end)
      %Extep{status: :ok, context: %{foo: 2, bar: 4}, message: nil}

  **Explanation**:
  - First `run/3` updates `:foo` from 1 to 2
  - Second `run/3` adds `:bar` with value 4 (using the updated foo value: 2 + 2)
  - Both operations succeed, context now contains both updated values

  ### Error with Named Function - Pipeline Stops
  When a named function returns an error, the pipeline stops and subsequent steps are skipped:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:foo, &return_error_tuple/1)
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 2} end)
      %Extep{status: :error, context: %{foo: 1}, message: %{return_error_tuple: "error message"}}

  **Explanation**:
  - First `run/3` calls `return_error_tuple/1` which returns `{:error, "error message"}`
  - Pipeline status becomes `:error`, original context is preserved
  - Error message is labeled with function name (`return_error_tuple`)
  - Second `run/3` is skipped because pipeline is already in error state

  ### Error with Anonymous Function - Pipeline Stops
  When an anonymous function returns an error, the error is labeled with the context key:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:foo, fn _ctx -> {:error, "error message"} end)
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 2} end)
      %Extep{status: :error, context: %{foo: 1}, message: %{foo: "error message"}}

  **Explanation**:
  - First `run/3` tries to update `:foo` but returns an error
  - Pipeline status becomes `:error`, original context is preserved
  - Error message is labeled with the context key (`:foo`)
  - Second `run/3` is skipped because pipeline is already in error state

  ### Halt with Custom Message - Pipeline Stops
  When a function returns halt, the pipeline stops gracefully with the halt message:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:foo, fn _ctx -> {:halt, {:ok, "halt message"}} end)
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 2} end)
      %Extep{status: :halted, context: %{foo: 1}, message: {:ok, "halt message"}}

  **Explanation**:
  - First `run/3` returns a halt tuple with `{:ok, "halt message"}`
  - Pipeline status becomes `:halted`, original context is preserved
  - Halt message can be any term (here it's `{:ok, "halt message"}`)
  - Second `run/3` is skipped because pipeline is already halted

  ## Pipeline Behavior

  - If the Extep struct already has `:halted` or `:error` status, this function does nothing
  - Only processes when the current status is `:ok`
  - On success, the context is updated with the new value under the specified key
  - On failure or halt, the context remains unchanged
  - Context keys can be new (adding) or existing (updating)
  """
  @spec run(t(), context_key(), context_mutator_fun()) :: t()
  def run(extep, ctx_key, fun)

  def run(%{tasks: [_ | _]} = extep, ctx_key, fun)
      when is_ok(extep) and is_atom(ctx_key) and is_ctx_fun(fun) do
    extep
    |> await()
    |> run(ctx_key, fun)
  end

  def run(extep, ctx_key, fun)
      when is_ok(extep) and is_atom(ctx_key) and is_ctx_fun(fun) do
    case apply(fun, [extep.context]) do
      {:ok, value} -> %{extep | context: Map.put(extep.context, ctx_key, value)}
      return -> interrupt(extep, return, fun, ctx_key)
    end
  end

  def run(extep, ctx_key, fun)
      when is_interrupted(extep) and is_atom(ctx_key) and is_ctx_fun(fun) do
    shutdown_tasks(extep)
  end

  @doc """
  Returns a final result from your pipeline with optional configuration.

  This function extracts the final result from your pipeline based on the pipeline's status:

  - **`:ok` status**: Executes the given function or returns the context value for the given key
  - **`:halted` status**: Returns the halt message (ignores all options)
  - **`:error` status**: Returns an error tuple, optionally with or without context labels

  ## Parameters

  - `extep` - The Extep struct containing your pipeline state
  - `fun_or_key` - Either a function `(context -> result)` or an atom key to extract from context
  - `opts` - Keyword list of options (defaults to `[]`)

  ## Options

  - `label_error` (boolean, default: `false`):
    - When `false`: Returns clean error messages like `{:error, "message"}`
    - When `true`: Returns labeled errors like `{:error, %{fun_name_or_step_name: "message"}}`

  ## Examples

  ### Successful Pipeline with Function
  When the pipeline succeeds, the function is executed with the context:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.return(fn ctx -> {:ok, ctx.bar + 2} end)
      {:ok, 4}

  ### Successful Pipeline with Context Key
  When the pipeline succeeds, the value for the given key is returned:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.run(:baz, fn ctx -> {:ok, ctx.bar + 2} end)
      ...> |> Extep.return(:bar)
      {:ok, 2}

  ### Error Pipeline with Default Behavior (Clean Errors)
  When the pipeline errors and no options are provided, returns clean error messages:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn _ctx -> {:error, "error message"} end)
      ...> |> Extep.return(:foo)
      {:error, "error message"}

  ### Error Pipeline with Function and Labeled Errors
  When `label_error: true` is set and a named function causes the error,
  the error is labeled with the function name:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.return(&return_error_tuple/1, label_error: true)
      {:error, %{return_error_tuple: "error message"}}

  ### Error Pipeline with Anonymous Function and Labeled Errors
  When `label_error: true` is set and an anonymous function causes the error,
  the error is labeled with `:no_label`:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.return(fn _ctx -> {:error, "error message"} end, label_error: true)
      {:error, %{no_label: "error message"}}

  ### Error Pipeline with Context Key and Labeled Errors
  When `label_error: true` is set and a step with a context key caused the error,
  the error is labeled with that step's name:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn _ctx -> {:error, "error message"} end)
      ...> |> Extep.return(:foo, label_error: true)
      {:error, %{bar: "error message"}}

  ### Halted Pipeline Returning Function Result
  When a function in the pipeline halts with a result, that result is returned directly:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.return(fn _ctx -> {:halt, {:ok, "halt message"}} end)
      {:ok, "halt message"}

  ### Halted Pipeline Returning Custom Tuple
  Halt messages can be any term, not just ok tuples:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.return(fn _ctx -> {:halt, {:cancel, "cancel message"}} end)
      {:cancel, "cancel message"}

  ### Previously Halted Pipeline
  When the pipeline was already halted in a previous step, the halt message is returned
  regardless of what you're trying to return:

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.run(:baz, fn _ctx -> {:halt, {:ok, "halt message"}} end)
      ...> |> Extep.return(:bar)
      {:ok, "halt message"}
  """
  @spec return(t(), context_mutator_fun() | context_key(), opts()) :: {:ok | :error, any()}
  def return(extep, fun_or_key, opts \\ []) do
    {status, {value, _context}} = return_with_context(extep, fun_or_key, opts)

    {status, value}
  end

  @doc """
  Returns a final result from your pipeline along with the context.

  This function works exactly like `return/3`, but returns the result as a tuple containing
  both the value and the context: `{status, {value, context}}`.

  This is useful when you need to inspect or use the pipeline context after extraction,
  particularly for debugging or when the context contains additional data needed by the caller.

  ## Parameters

  - `extep` - The Extep struct containing your pipeline state
  - `fun_or_key` - Either a function `(context -> result)` or an atom key to extract from context
  - `opts` - Keyword list of options (defaults to `[]`)

  ## Options

  - `label_error` (boolean, default: `false`):
    - When `false`: Returns clean error messages like `{:error, {"message", context}}`
    - When `true`: Returns labeled errors like `{:error, {%{step_name: "message"}, context}}`

  ## Examples

  ### Successful Pipeline with Context

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn ctx -> {:ok, ctx.foo + 1} end)
      ...> |> Extep.return_with_context(:bar)
      {:ok, {2, %{foo: 1, bar: 2}}}

  ### Error Pipeline with Context

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn _ctx -> {:error, "error message"} end)
      ...> |> Extep.return_with_context(:foo)
      {:error, {"error message", %{foo: 1}}}

  ### Halted Pipeline with Non-Tuple Message

      iex> Extep.new(%{foo: 1})
      ...> |> Extep.run(:bar, fn _ctx -> {:halt, "halt message"} end)
      ...> |> Extep.return_with_context(:bar)
      {:no_status, {"halt message", %{foo: 1}}}
  """
  @spec return_with_context(t(), context_mutator_fun() | context_key(), opts()) ::
          {:ok | :error | atom(), {any(), context()}}
  def return_with_context(extep, fun_or_key, opts \\ [])

  def return_with_context(%{tasks: [_ | _]} = extep, fun, opts)
      when is_ok(extep) and is_ctx_fun(fun) do
    extep
    |> await()
    |> return_with_context(fun, opts)
  end

  def return_with_context(extep, fun, opts) when is_ok(extep) and is_ctx_fun(fun) do
    case apply(fun, [extep.context]) do
      {:ok, value} ->
        {:ok, {value, extep.context}}

      return ->
        extep
        |> interrupt(return, fun, nil)
        |> return_interrupted(opts)
    end
  end

  def return_with_context(extep, fun, opts) when is_interrupted(extep) and is_ctx_fun(fun) do
    extep
    |> shutdown_tasks()
    |> return_interrupted(opts)
  end

  def return_with_context(%{tasks: [_ | _]} = extep, ctx_key, opts)
      when is_ok(extep) and is_atom(ctx_key) do
    extep
    |> await()
    |> return_with_context(ctx_key, opts)
  end

  def return_with_context(extep, ctx_key, _opts) when is_ok(extep) and is_atom(ctx_key) do
    {:ok, {Map.fetch!(extep.context, ctx_key), extep.context}}
  end

  def return_with_context(extep, ctx_key, opts) when is_interrupted(extep) and is_atom(ctx_key) do
    extep
    |> shutdown_tasks()
    |> return_interrupted(opts)
  end

  defp interrupt(%Extep{} = extep, {:halt, message}, _fun, _ctx_key) do
    %{extep | status: :halted, message: message}
  end

  defp interrupt(%Extep{} = extep, {:error, message}, fun, ctx_key) do
    message_key = handle_message_key(fun, ctx_key)

    %{extep | status: :error, message: Map.new([{message_key, message}])}
  end

  defp return_interrupted(%Extep{status: :halted, message: {status, message}} = extep, _opts) do
    {status, {message, extep.context}}
  end

  defp return_interrupted(%Extep{status: :halted, message: message} = extep, _opts) do
    {:no_status, {message, extep.context}}
  end

  defp return_interrupted(%Extep{status: :error} = extep, opts) do
    case Keyword.get(opts, :label_error, false) do
      true -> {:error, {extep.message, extep.context}}
      false -> extract_error_message(extep)
    end
  end

  defp extract_error_message(%Extep{message: message, context: context}) when is_map(message) do
    case Map.to_list(message) do
      [{_key, error_message}] -> {:error, {error_message, context}}
      _ -> {:error, {message, context}}
    end
  end

  defp extract_error_message(%Extep{message: message, context: context}) do
    {:error, {message, context}}
  end

  defp handle_message_key(fun, ctx_key) when is_function(fun) do
    info = Function.info(fun)
    type = Keyword.fetch!(info, :type)
    env = Keyword.fetch!(info, :env)
    name = Keyword.fetch!(info, :name)
    ctx_key = handle_context_key(ctx_key)

    cond do
      type == :external ->
        name

      type == :local and is_atom(name) and String.contains?(Atom.to_string(name), "-fun-") ->
        ctx_key

      type == :local and env != [] ->
        ctx_key

      true ->
        name
    end
  end

  defp handle_context_key(nil), do: :no_label
  defp handle_context_key(ctx_key) when is_atom(ctx_key), do: ctx_key
end
