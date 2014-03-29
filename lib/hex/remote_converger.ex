defmodule Hex.RemoteConverger do
  @moduledoc false

  @behaviour Mix.RemoteConverger

  @registry_updated :registry_updated

  def remote?({ app, _opts }) do
    remote?(app)
  end

  def remote?(app) when is_atom(app) do
    Hex.Registry.exists?("#{app}")
  end

  def converge(deps) do
    unless File.exists?(Hex.Registry.path()) do
      if update_registry("Fetching registry...") == :error do
        raise Mix.Error
      end
    end

    main      = Mix.project[:deps] || []
    lock      = Mix.Dep.Lock.read
    locked    = Hex.Mix.from_lock(lock)
    reqs      = Hex.Mix.deps_to_requests(deps)
    overriden = Hex.Mix.overriden(main)

    print_info(reqs, locked)

    if resolved = Hex.Resolver.resolve(reqs, overriden, locked) do
      print_success(resolved, locked)
      Hex.Mix.annotate_deps(resolved, deps)
    else
      raise Mix.Error, message: "Dependency resolution failed, relax the version requirements or unlock dependencies"
    end
  end

  def update_registry(info \\ nil) do
    if :application.get_env(:hex, :registry_updated) == { :ok, true } do
      { :ok, :cached }
    else
      :application.set_env(:hex, :registry_updated, true)

      if info, do: Mix.shell.info(info)

      case Hex.API.get_registry do
        { 200, body } ->
          data = :zlib.gunzip(body)
          File.write!(Hex.Registry.path, data)
          Mix.shell.info("Registry update was successful!")
          { :ok, :new }
        { code, body } ->
          Mix.shell.error("Registry update failed! (#{code})")
          Mix.Tasks.Hex.Util.print_error_result(code, body)
          :error
      end
    end
  end

  defp print_info(reqs, locked) do
    resolve =
      Enum.flat_map(reqs, fn { app, _req} ->
        if Dict.has_key?(locked, app), do: [], else: [app]
      end)

    if resolve != [] do
      Mix.shell.info "Running dependency resolution for unlocked dependencies: " <> Enum.join(resolve, ", ")
    end
  end

  defp print_success(resolved, locked) do
    resolved = Dict.drop(resolved, Dict.keys(locked))
    if resolved != [] do
      Mix.shell.info "Dependency resolution completed successfully"
      Enum.each(resolved, fn { dep, version } ->
        Mix.shell.info "  #{dep} : v#{version}"
      end)
    end
  end
end
