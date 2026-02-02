defmodule ExtepTest do
  use ExUnit.Case, async: true
  doctest Extep

  describe "new/0" do
    test "returns an `Extep` struct with default values" do
      assert Extep.new() == %Extep{status: :ok, context: %{}, message: nil}
    end
  end

  describe "new/1" do
    test "returns an `Extep` struct when given a Map" do
      context = %{key: "value"}

      assert Extep.new(context) == %Extep{status: :ok, context: context, message: nil}
    end
  end

  describe "run/2" do
    test "doesn't modify the context when the given function returns an ok tuple" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.run(extep, fn _context -> {:ok, "return"} end) == %Extep{
               status: :ok,
               context: %{key: "value"},
               message: nil
             }
    end

    test "doesn't modify the context when the given function returns `:ok`" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.run(extep, fn _context -> :ok end) == %Extep{
               status: :ok,
               context: %{key: "value"},
               message: nil
             }
    end

    test "doesn't modify the context when the given function returns a halt tuple and updates the message field" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.run(extep, fn _context -> {:halt, {:ok, "halt message"}} end) == %Extep{
               status: :halted,
               context: %{key: "value"},
               message: {:ok, "halt message"}
             }
    end

    test "doesn't modify context when the given function returns an error tuple and puts the error message
          under a key with the name of the functions when it's a defined module function" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.run(extep, &return_error_tuple/1) == %Extep{
               status: :error,
               context: %{key: "value"},
               message: %{return_error_tuple: "error message"}
             }
    end

    test "doesn't modify context when the given function returns an error tuple and and updates the message field" do
      extep = %Extep{status: :ok, context: %{}, message: nil}

      assert Extep.run(extep, fn _context -> {:error, "error message"} end) == %Extep{
               status: :error,
               context: %{},
               message: %{no_label: "error message"}
             }
    end
  end

  describe "run/3" do
    test "raises when the given function returns ok" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert_raise FunctionClauseError, fn -> Extep.run(extep, :key, fn _context -> :ok end) end
    end

    test "updates an existing context field when the given function returns an ok tuple" do
      extep = %Extep{status: :ok, context: %{existing_key: "value"}, message: nil}

      assert Extep.run(extep, :existing_key, fn _context -> {:ok, "new value"} end) == %Extep{
               status: :ok,
               context: %{existing_key: "new value"},
               message: nil
             }
    end

    test "adds a new context context field when the given function returns an ok tuple" do
      extep = %Extep{status: :ok, context: %{existing_key: "value"}, message: nil}

      assert Extep.run(extep, :new_key, fn _context -> {:ok, "new value"} end) == %Extep{
               status: :ok,
               context: %{existing_key: "value", new_key: "new value"},
               message: nil
             }
    end

    test "doesn't modify context when the given function returns halt tuple" do
      extep = %Extep{status: :ok, context: %{existing_key: "value"}, message: nil}

      assert Extep.run(extep, :existing_key, fn _context -> {:halt, {:ok, "halt message"}} end) ==
               %Extep{
                 status: :halted,
                 context: %{existing_key: "value"},
                 message: {:ok, "halt message"}
               }
    end

    test "doesn't modify context when the given function returns an error tuple and puts the error message
          under a key with the name of the functions when it's a defined module function" do
      extep = %Extep{status: :ok, context: %{}, message: nil}

      assert Extep.run(extep, :new_key, &return_error_tuple/1) == %Extep{
               status: :error,
               context: %{},
               message: %{return_error_tuple: "error message"}
             }
    end

    test "doesn't modify context when the given function returns an error tuple and puts the error message
          under a key with the name of the step when it's anonymous function" do
      extep = %Extep{status: :ok, context: %{}, message: nil}

      assert Extep.run(extep, :new_key, fn _context -> {:error, "error message"} end) == %Extep{
               status: :error,
               context: %{},
               message: %{new_key: "error message"}
             }
    end
  end

  describe "async/2" do
    test "starts a task that doesn't modify the context" do
      extep = %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}

      assert %Extep{
               status: :ok,
               context: %{},
               tasks: [%Task{} = task],
               message: nil
             } =
               Extep.async(extep, fn context ->
                 assert context == extep.context

                 :ok
               end)

      assert Task.await(task) == extep
    end

    test "ensures :timeout option threshold and exits on timeout" do
      extep = %Extep{status: :ok, context: %{}, tasks: [], message: nil}

      extep =
        Extep.async(extep, fn _context ->
          Process.sleep(50)
          :ok
        end)

      assert {:timeout, {Task, :await_many, _}} = catch_exit(Extep.await(extep, timeout: 10))
    end

    test "starts a task that changes the extep status" do
      extep = %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}

      assert %Extep{
               status: :ok,
               context: %{},
               tasks: [%Task{} = task],
               message: nil
             } = Extep.async(extep, fn _context -> {:error, "error message"} end)

      assert Task.await(task) == %Extep{
               status: :error,
               context: %{key: "value"},
               tasks: [],
               message: %{no_label: "error message"}
             }
    end

    test "does not start tasks with interrupted status" do
      extep = %Extep{status: :halted, context: %{}, tasks: [], message: nil}

      assert Extep.async(extep, fn _context -> :ok end) == %Extep{
               status: :halted,
               context: %{},
               tasks: [],
               message: nil
             }
    end
  end

  describe "async/3" do
    test "starts a task that modifies the context" do
      extep = %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}

      assert %Extep{
               status: :ok,
               context: %{},
               tasks: [%Task{} = task],
               message: nil
             } =
               Extep.async(extep, :new_key, fn context ->
                 assert context == extep.context

                 {:ok, "new value"}
               end)

      assert Task.await(task) == %Extep{
               status: :ok,
               context: %{key: "value", new_key: "new value"},
               tasks: [],
               message: nil
             }
    end

    test "starts a task that changes the extep status to error" do
      extep = %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}

      assert %Extep{
               status: :ok,
               context: %{},
               tasks: [%Task{} = task],
               message: nil
             } = Extep.async(extep, :new_key, fn _context -> {:error, "error message"} end)

      assert Task.await(task) == %Extep{
               status: :error,
               context: %{key: "value"},
               tasks: [],
               message: %{new_key: "error message"}
             }
    end

    test "does not start tasks with interrupted status" do
      extep = %Extep{status: :halted, context: %{}, tasks: [], message: nil}

      assert Extep.async(extep, :new_key, fn _context -> {:ok, "new value"} end) == %Extep{
               status: :halted,
               context: %{},
               tasks: [],
               message: nil
             }
    end
  end

  describe "await/2" do
    test "await with no tasks returns same extep" do
      extep = %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}

      assert Extep.await(extep) == extep
    end

    test "await shuts down tasks when extep is interrupted" do
      task = Task.async(fn -> :ok end)
      extep = %Extep{status: :error, context: %{}, tasks: [task], message: nil}

      assert Extep.await(extep) ==
               %Extep{
                 status: :error,
                 context: %{},
                 tasks: [],
                 message: nil
               }
    end

    test "await processes async/2 tasks" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(fn _context -> :ok end)

      assert Extep.await(extep) == %Extep{
               status: :ok,
               context: %{key: "value"},
               tasks: [],
               message: nil
             }
    end

    test "await processes async/3 tasks" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(:new_key, fn _context -> {:ok, "new value"} end)

      assert Extep.await(extep) == %Extep{
               status: :ok,
               context: %{key: "value", new_key: "new value"},
               tasks: [],
               message: nil
             }
    end

    test "await processes multiple tasks" do
      extep =
        %Extep{status: :ok, context: %{first_key: "first value"}, tasks: [], message: nil}
        |> Extep.async(:second_key, fn _context -> {:ok, "second value"} end)
        |> Extep.async(fn _context -> :ok end)
        |> Extep.async(:third_key, fn _context -> {:ok, "third value"} end)

      assert Extep.await(extep) == %Extep{
               status: :ok,
               context: %{
                 first_key: "first value",
                 second_key: "second value",
                 third_key: "third value"
               },
               tasks: [],
               message: nil
             }
    end

    test "when a run/3 async step fails" do
      extep =
        %Extep{status: :ok, context: %{first_key: "first value"}, tasks: [], message: nil}
        |> Extep.async(:second_key, fn _context -> {:error, "error message"} end)
        |> Extep.async(fn _context -> :ok end)
        |> Extep.async(:third_key, fn _context -> {:ok, "third value"} end)

      assert Extep.await(extep) == %Extep{
               status: :error,
               context: %{first_key: "first value"},
               tasks: [],
               message: %{second_key: "error message"}
             }
    end

    test "when a run/2 async step fails" do
      extep =
        %Extep{status: :ok, context: %{first_key: "first value"}, tasks: [], message: nil}
        |> Extep.async(:second_key, fn _context -> {:ok, "second value"} end)
        |> Extep.async(fn _context -> {:error, "error message"} end)
        |> Extep.async(:third_key, fn _context -> {:ok, "third value"} end)

      assert Extep.await(extep) == %Extep{
               status: :error,
               context: %{first_key: "first value", second_key: "second value"},
               tasks: [],
               message: %{no_label: "error message"}
             }
    end

    test "when multiple async steps fails, stops and return the first failure" do
      extep =
        %Extep{status: :ok, context: %{first_key: "first value"}, tasks: [], message: nil}
        |> Extep.async(:second_key, fn _context -> {:error, "error message"} end)
        |> Extep.async(fn _context -> {:error, "error message"} end)
        |> Extep.async(:third_key, fn _context -> {:ok, "third value"} end)

      assert Extep.await(extep) == %Extep{
               status: :error,
               context: %{first_key: "first value"},
               tasks: [],
               message: %{second_key: "error message"}
             }
    end

    test "await handles error in async/2 task" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(fn _context -> {:error, "error message"} end)

      assert Extep.await(extep) == %Extep{
               status: :error,
               context: %{key: "value"},
               tasks: [],
               message: %{no_label: "error message"}
             }
    end

    test "await handles error in async/3 task" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(:new_key, fn _context -> {:error, "error message"} end)

      assert Extep.await(extep) == %Extep{
               status: :error,
               context: %{key: "value"},
               tasks: [],
               message: %{new_key: "error message"}
             }
    end
  end

  describe "return/2 - for context key" do
    test "returns the value from the given context key as an ok tuple" do
      context = %{key: "value", another_key: "antother value"}
      extep = %Extep{status: :ok, context: context, message: nil}

      assert Extep.return(extep, :key) == {:ok, "value"}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with a tuple" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: {:ok, "halt message"}}

      assert Extep.return(extep, :key) == {:ok, "halt message"}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with string message" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: "halt message"}

      assert Extep.return(extep, :key) == {:no_status, "halt message"}
    end

    test "returns an unlabeled error tuple when the `%Extep{}` status is `:error` (default behavior)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return(extep, :key) == {:error, "error message"}
    end

    test "handles extep with pending tasks before returning value" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(:new_key, fn _context -> {:ok, "new value"} end)

      assert Extep.return(extep, :new_key) == {:ok, "new value"}
    end

    test "handles error in tasks" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(:new_key, fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, :key) == {:error, "error message"}
    end
  end

  describe "return/2 - for function" do
    test "returns the result of the given function" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end) == {:ok, "new value"}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with a tuple" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: {:ok, "halt message"}}

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end) == {:ok, "halt message"}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with string message" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: "halt message"}

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end) ==
               {:no_status, "halt message"}
    end

    test "returns an unlabeled error tuple when the `%Extep{}` status is `:error` (default behavior)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end) ==
               {:error, "error message"}
    end

    test "handles extep with pending tasks before returning value" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:ok, "value"} end)

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end) == {:ok, "new value"}
    end

    test "handles error in tasks" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end) ==
               {:error, "error message"}
    end
  end

  describe "return/3 - with label_error option" do
    test "returns unlabeled error by default (label_error defaults to false)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return(extep, :key) == {:error, "error message"}
    end

    test "returns unlabeled error when label_error: false (explicit)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return(extep, :key, label_error: false) == {:error, "error message"}
    end

    test "returns labeled error when label_error: true" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return(extep, :key, label_error: true) ==
               {:error, %{some_key: "error message"}}
    end

    test "works with functions when label_error: false" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return(extep, fn _ctx -> {:ok, "result"} end, label_error: false) ==
               {:error, "error message"}
    end

    test "works with functions when label_error: true" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return(extep, fn _ctx -> {:ok, "result"} end, label_error: true) ==
               {:error, %{some_key: "error message"}}
    end

    test "returns labeled error when a named function returns an error tuple and label_error: true" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return(extep, &return_error_tuple/1, label_error: true) ==
               {:error, %{return_error_tuple: "error message"}}
    end

    test "returns labeled error when an anonymous function returns an error tuple and label_error: true" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return(extep, fn _ctx -> {:error, "error message"} end, label_error: true) ==
               {:error, %{no_label: "error message"}}
    end

    test "halted status ignores label_error option" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: {:ok, "halt message"}}

      assert Extep.return(extep, :key, label_error: true) == {:ok, "halt message"}
      assert Extep.return(extep, :key, label_error: false) == {:ok, "halt message"}
    end

    test "halted status ignores label_error option with string message" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: "halt message"}

      assert Extep.return(extep, :key, label_error: true) == {:no_status, "halt message"}
      assert Extep.return(extep, :key, label_error: false) == {:no_status, "halt message"}
    end

    test "ok status ignores label_error option and returns context value" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return(extep, :key, label_error: true) == {:ok, "value"}
      assert Extep.return(extep, :key, label_error: false) == {:ok, "value"}
    end

    test "handles async task error with label_error: false for context key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, :key, label_error: false) == {:error, "error message"}
    end

    test "handles async task error with label_error: true for context key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, :key, label_error: true) == {:error, %{key: "error message"}}
    end

    test "handles async task error with label_error: true for context key and step without key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, :key, label_error: true) ==
               {:error, %{no_label: "error message"}}
    end

    test "handles async task error with label_error: false for function" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end, label_error: false) ==
               {:error, "error message"}
    end

    test "handles async task error with label_error: true for function" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end, label_error: true) ==
               {:error, %{key: "error message"}}
    end

    test "handles async task error with label_error: true for function and step without key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(fn _context -> {:error, "error message"} end)

      assert Extep.return(extep, fn _context -> {:ok, "new value"} end, label_error: true) ==
               {:error, %{no_label: "error message"}}
    end
  end

  describe "return_with_context/3 - for context key" do
    test "returns the value from the given context key as an ok tuple" do
      context = %{key: "value", another_key: "antother value"}
      extep = %Extep{status: :ok, context: context, message: nil}

      assert Extep.return_with_context(extep, :key) == {:ok, {"value", context}}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with a tuple" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: {:ok, "halt message"}}

      assert Extep.return_with_context(extep, :key) == {:ok, {"halt message", extep.context}}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with string message" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: "halt message"}

      assert Extep.return_with_context(extep, :key) ==
               {:no_status, {"halt message", extep.context}}
    end

    test "returns an unlabeled error tuple when the `%Extep{}` status is `:error` (default behavior)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return_with_context(extep, :key) == {:error, {"error message", extep.context}}
    end

    test "handles extep with pending tasks before returning value" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(:new_key, fn _context -> {:ok, "new value"} end)

      assert {:ok, {"new value", context}} = Extep.return_with_context(extep, :new_key)
      assert context.new_key == "new value"
    end

    test "handles error in tasks" do
      extep =
        %Extep{status: :ok, context: %{key: "value"}, tasks: [], message: nil}
        |> Extep.async(:new_key, fn _context -> {:error, "error message"} end)

      assert {:error, {"error message", context}} = Extep.return_with_context(extep, :key)
      assert context == %{key: "value"}
    end
  end

  describe "return_with_context/3 - for function" do
    test "returns the result of the given function" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end) ==
               {:ok, {"new value", extep.context}}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with a tuple" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: {:ok, "halt message"}}

      assert Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end) ==
               {:ok, {"halt message", extep.context}}
    end

    test "returns the halted value when `%Extep{}` status is `:halted` with string message" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: "halt message"}

      assert Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end) ==
               {:no_status, {"halt message", extep.context}}
    end

    test "returns an unlabeled error tuple when the `%Extep{}` status is `:error` (default behavior)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end) ==
               {:error, {"error message", extep.context}}
    end

    test "handles extep with pending tasks before returning value" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:ok, "value"} end)

      assert {:ok, {"new value", context}} =
               Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end)

      assert context.key == "value"
    end

    test "handles error in tasks" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert {:error, {"error message", context}} =
               Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end)

      assert context == %{}
    end
  end

  describe "return_with_context/3 - with label_error option" do
    test "returns unlabeled error by default (label_error defaults to false)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return_with_context(extep, :key) == {:error, {"error message", extep.context}}
    end

    test "returns unlabeled error when label_error: false (explicit)" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return_with_context(extep, :key, label_error: false) ==
               {:error, {"error message", extep.context}}
    end

    test "returns labeled error when label_error: true" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return_with_context(extep, :key, label_error: true) ==
               {:error, {%{some_key: "error message"}, extep.context}}
    end

    test "works with functions when label_error: false" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return_with_context(extep, fn _ctx -> {:ok, "result"} end, label_error: false) ==
               {:error, {"error message", extep.context}}
    end

    test "works with functions when label_error: true" do
      extep = %Extep{
        status: :error,
        context: %{key: "value"},
        message: %{some_key: "error message"}
      }

      assert Extep.return_with_context(extep, fn _ctx -> {:ok, "result"} end, label_error: true) ==
               {:error, {%{some_key: "error message"}, extep.context}}
    end

    test "returns labeled error when a named function returns an error tuple and label_error: true" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return_with_context(extep, &return_error_tuple/1, label_error: true) ==
               {:error, {%{return_error_tuple: "error message"}, extep.context}}
    end

    test "returns labeled error when an anonymous function returns an error tuple and label_error: true" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return_with_context(extep, fn _ctx -> {:error, "error message"} end,
               label_error: true
             ) ==
               {:error, {%{no_label: "error message"}, extep.context}}
    end

    test "halted status ignores label_error option" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: {:ok, "halt message"}}

      assert Extep.return_with_context(extep, :key, label_error: true) ==
               {:ok, {"halt message", extep.context}}

      assert Extep.return_with_context(extep, :key, label_error: false) ==
               {:ok, {"halt message", extep.context}}
    end

    test "halted status ignores label_error option with string message" do
      extep = %Extep{status: :halted, context: %{key: "value"}, message: "halt message"}

      assert Extep.return_with_context(extep, :key, label_error: true) ==
               {:no_status, {"halt message", extep.context}}

      assert Extep.return_with_context(extep, :key, label_error: false) ==
               {:no_status, {"halt message", extep.context}}
    end

    test "ok status ignores label_error option and returns context value" do
      extep = %Extep{status: :ok, context: %{key: "value"}, message: nil}

      assert Extep.return_with_context(extep, :key, label_error: true) ==
               {:ok, {"value", extep.context}}

      assert Extep.return_with_context(extep, :key, label_error: false) ==
               {:ok, {"value", extep.context}}
    end

    test "handles async task error with label_error: false for context key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert {:error, {"error message", context}} =
               Extep.return_with_context(extep, :key, label_error: false)

      assert context == %{}
    end

    test "handles async task error with label_error: true for context key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert {:error, {%{key: "error message"}, context}} =
               Extep.return_with_context(extep, :key, label_error: true)

      assert context == %{}
    end

    test "handles async task error with label_error: true for context key and step without key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(fn _context -> {:error, "error message"} end)

      assert {:error, {%{no_label: "error message"}, context}} =
               Extep.return_with_context(extep, :key, label_error: true)

      assert context == %{}
    end

    test "handles async task error with label_error: false for function" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert {:error, {"error message", context}} =
               Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end,
                 label_error: false
               )

      assert context == %{}
    end

    test "handles async task error with label_error: true for function" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(:key, fn _context -> {:error, "error message"} end)

      assert {:error, {%{key: "error message"}, context}} =
               Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end,
                 label_error: true
               )

      assert context == %{}
    end

    test "handles async task error with label_error: true for function and step without key" do
      extep =
        %Extep{status: :ok, context: %{}, tasks: [], message: nil}
        |> Extep.async(fn _context -> {:error, "error message"} end)

      assert {:error, {%{no_label: "error message"}, context}} =
               Extep.return_with_context(extep, fn _context -> {:ok, "new value"} end,
                 label_error: true
               )

      assert context == %{}
    end
  end

  describe "integration flows" do
    test "success" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params/1)
        |> Extep.async(:user, &fetch_user/1)
        |> Extep.async(:items, &fetch_items/1)
        |> Extep.await()
        |> Extep.async(fn %{user: _} -> :ok end)
        |> Extep.async(:items_codes, fn %{items: items} -> {:ok, Enum.map(items, & &1.code)} end)
        |> Extep.run(fn %{items_codes: _} -> :ok end)
        |> Extep.async(fn _ -> :ok end)
        |> Extep.async(:whatever, fn _ -> {:ok, "whatever"} end)
        |> Extep.return(&create_subscription/1, label_error: true)

      assert return ==
               {:ok,
                %{
                  id: 123,
                  object: "subscription",
                  user_id: 1,
                  items: [%{code: "item1"}, %{code: "item2"}]
                }}
    end

    test "step failure" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params_failure/1)
        |> Extep.async(:user, &fetch_user/1)
        |> Extep.async(:items, &fetch_items/1)
        |> Extep.return(&create_subscription/1, label_error: true)

      assert return == {:error, %{validate_params_failure: "invalid params"}}
    end

    test "async step failure" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params/1)
        |> Extep.async(:user, &fetch_user/1)
        |> Extep.async(:items, &fetch_items_failure/1)
        |> Extep.return(&create_subscription/1, label_error: true)

      assert return == {:error, %{fetch_items_failure: "items not found"}}
    end

    test "multiple async steps failures" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params/1)
        |> Extep.async(:user, &fetch_user_failure/1)
        |> Extep.async(:items, &fetch_items_failure/1)
        |> Extep.return(&create_subscription/1, label_error: true)

      assert return == {:error, %{fetch_user_failure: "user not found"}}
    end

    test "success with return_with_context" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params/1)
        |> Extep.async(:user, &fetch_user/1)
        |> Extep.async(:items, &fetch_items/1)
        |> Extep.await()
        |> Extep.async(fn %{user: _} -> :ok end)
        |> Extep.async(:items_codes, fn %{items: items} -> {:ok, Enum.map(items, & &1.code)} end)
        |> Extep.run(fn %{items_codes: _} -> :ok end)
        |> Extep.async(fn _ -> :ok end)
        |> Extep.async(:whatever, fn _ -> {:ok, "whatever"} end)
        |> Extep.return_with_context(&create_subscription/1, label_error: true)

      assert {:ok,
              {%{
                 id: 123,
                 object: "subscription",
                 user_id: 1,
                 items: [%{code: "item1"}, %{code: "item2"}]
               }, context}} = return

      assert context.params == params
      assert context.user == %{id: 1, name: "Alice"}
      assert context.items == [%{code: "item1"}, %{code: "item2"}]
    end

    test "step failure with return_with_context" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params_failure/1)
        |> Extep.async(:user, &fetch_user/1)
        |> Extep.async(:items, &fetch_items/1)
        |> Extep.return_with_context(&create_subscription/1, label_error: true)

      assert {:error, {%{validate_params_failure: "invalid params"}, context}} = return
      assert context.params == params
    end

    test "async step failure with return_with_context" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params/1)
        |> Extep.async(:user, &fetch_user/1)
        |> Extep.async(:items, &fetch_items_failure/1)
        |> Extep.return_with_context(&create_subscription/1, label_error: true)

      assert {:error, {%{fetch_items_failure: "items not found"}, context}} = return
      assert context.params == params
      assert context.user == %{id: 1, name: "Alice"}
    end

    test "multiple async steps failures with return_with_context" do
      params = %{user_id: 1, plan: "super-power-plus"}

      return =
        Extep.new(%{params: params})
        |> Extep.run(:params, &validate_params/1)
        |> Extep.async(:user, &fetch_user_failure/1)
        |> Extep.async(:items, &fetch_items_failure/1)
        |> Extep.return_with_context(&create_subscription/1, label_error: true)

      assert {:error, {%{fetch_user_failure: "user not found"}, context}} = return
      assert context.params == params
    end
  end

  # Test helpers

  def return_error_tuple(_ctx), do: {:error, "error message"}

  def validate_params(ctx), do: {:ok, ctx.params}
  def validate_params_failure(_ctx), do: {:error, "invalid params"}

  def fetch_user(_ctx), do: {:ok, %{id: 1, name: "Alice"}}
  def fetch_user_failure(_ctx), do: {:error, "user not found"}

  def fetch_items(_ctx), do: {:ok, [%{code: "item1"}, %{code: "item2"}]}
  def fetch_items_failure(_ctx), do: {:error, "items not found"}

  def create_subscription(_ctx) do
    {:ok,
     %{id: 123, object: "subscription", user_id: 1, items: [%{code: "item1"}, %{code: "item2"}]}}
  end

  def notify_user(_ctx), do: :ok
end
