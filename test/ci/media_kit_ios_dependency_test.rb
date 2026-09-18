require 'digest'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# 直接测试已打补丁的依赖；无需安装 Flutter 或 CocoaPods。
source_dir = ARGV.shift or abort '用法：ruby test/ci/media_kit_ios_dependency_test.rb <插件的 ios 目录>'
MAKEFILE_SOURCE = File.read(File.join(source_dir, 'Makefile'))
PODSPEC_SOURCE = File.read(File.join(source_dir, 'media_kit_libs_ios_video.podspec'))

require 'minitest/autorun'

describe 'iOS libmpv 安装失败处理' do
  before do
    @directory = Dir.mktmpdir('piliplus-mpv-test-')
    File.write(File.join(@directory, 'Makefile'), MAKEFILE_SOURCE)
    File.write(File.join(@directory, 'plugin.podspec'), PODSPEC_SOURCE)
    FileUtils.mkdir_p(File.join(@directory, 'bin'))
    curl = File.join(@directory, 'bin', 'curl')
    File.write(curl, <<~RUBY)
      #!#{RbConfig.ruby}
      exit ENV.fetch('LIBMPV_TEST_STATUS').to_i unless ENV.fetch('LIBMPV_TEST_STATUS') == '0'
      File.write(ARGV.fetch(ARGV.index('-o') + 1), ENV.fetch('LIBMPV_TEST_BODY'))
    RUBY
    File.chmod(0o755, curl)
    @environment = {
      'PATH' => "#{@directory}/bin:#{ENV.fetch('PATH')}",
      'LIBMPV_TEST_STATUS' => '0',
      'LIBMPV_TEST_BODY' => '损坏的下载内容',
      'MAKEFLAGS' => nil
    }
  end

  after do
    FileUtils.remove_entry(@directory)
  end

  def evaluate_podspec
    # 只隔离 CocoaPods 的 DSL，实际执行依赖的 make、校验及解压命令。
    Open3.capture2e(@environment, RbConfig.ruby, '-e', <<~RUBY, chdir: @directory)
      module Pod
        class Spec
          def self.new
            yield Object.new
          end
        end
      end
      load 'plugin.podspec'
    RUBY
  end

  def assert_installation_stopped(output, status)
    refute status.success?, output
    assert_includes output, '准备 iOS libmpv 框架失败'
    refute Dir.exist?(File.join(@directory, 'Frameworks', '.symlinks'))
  end

  it '下载命令失败时终止 Pod 安装' do
    @environment['LIBMPV_TEST_STATUS'] = '22'
    output, status = evaluate_podspec
    assert_installation_stopped(output, status)
    refute_includes output, 'shasum -a 256'
  end

  it '校验失败时终止 Pod 安装且不保留可用缓存' do
    output, status = evaluate_podspec
    assert_installation_stopped(output, status)
    assert_includes output, 'FAILED'
    refute File.exist?(File.join(@directory, '.cache/xcframeworks/libmpv-xcframeworks-v0.7.2-ios-universal.tar.gz'))
  end

  it '校验通过但解压失败时也终止 Pod 安装' do
    digest = Digest::SHA256.hexdigest(@environment.fetch('LIBMPV_TEST_BODY'))
    @environment['MAKEFLAGS'] = "MPV_XCFRAMEWORKS_SHA256SUM=#{digest}"
    output, status = evaluate_podspec
    assert_installation_stopped(output, status)
    assert_includes output, '.cache/xcframeworks/libmpv.tar.gz.tmp: OK'
    assert_includes output, 'tar '
  end
end
