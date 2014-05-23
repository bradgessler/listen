require 'spec_helper'

describe Listen::TCP::Listener do

  let(:host) { '10.0.0.2' }
  let(:port) { 4000 }

  subject { described_class.new("#{host}:#{port}", :recipient, options) }
  let(:options) { {} }
  let(:registry) { instance_double(Celluloid::Registry, :[]= => true) }

  let(:supervisor) do
    instance_double(Celluloid::SupervisionGroup, add: true, pool: true)
  end

  let(:record) { instance_double(Listen::Record, terminate: true, build: true) }
  let(:silencer) { instance_double(Listen::Silencer, terminate: true) }
  let(:adapter) { instance_double(Listen::Adapter::Base) }
  let(:async) { instance_double(Listen::TCP::Broadcaster, broadcast: true) }
  let(:broadcaster) { instance_double(Listen::TCP::Broadcaster, async: async) }
  let(:change_pool) { instance_double(Listen::Change, terminate: true) }
  let(:change_pool_async) { instance_double('ChangePoolAsync') }
  before do
    allow(Celluloid::Registry).to receive(:new) { registry }
    allow(Celluloid::SupervisionGroup).to receive(:run!) { supervisor }
    allow(registry).to receive(:[]).with(:silencer) { silencer }
    allow(registry).to receive(:[]).with(:adapter) { adapter }
    allow(registry).to receive(:[]).with(:record) { record }
    allow(registry).to receive(:[]).with(:change_pool) { change_pool }
    allow(registry).to receive(:[]).with(:broadcaster) { broadcaster }
  end

  describe '#initialize' do
    describe '#mode' do
      subject { super().mode }
      it { is_expected.to be :recipient }
    end

    describe '#host' do
      subject { super().host }
      it { is_expected.to eq host }
    end

    describe '#port' do
      subject { super().port }
      it { is_expected.to eq port }
    end

    it 'raises on invalid mode' do
      expect do
        described_class.new(port, :foo)
      end.to raise_error ArgumentError
    end

    it 'raises on omitted target' do
      expect do
        described_class.new(nil, :recipient)
      end.to raise_error ArgumentError
    end
  end

  context 'when broadcaster' do
    subject { described_class.new(port, :broadcaster) }

    it { is_expected.to be_a_broadcaster }
    it { is_expected.not_to be_a_recipient }

    it 'does not force TCP adapter through options' do
      expect(subject.options).not_to include(force_tcp: true)
    end

    context 'when host is omitted' do
      describe '#host' do
        subject { super().host }
        it { is_expected.to be_nil }
      end
    end

    describe '#start' do
      before do
        allow(subject).to receive(:_start_adapter)
        allow(broadcaster).to receive(:start)
      end

      it 'registers broadcaster' do
        expect(supervisor).to receive(:add).
          with(Listen::TCP::Broadcaster, as: :broadcaster, args: [nil, port])
        subject.start
      end

      it 'starts broadcaster' do
        expect(broadcaster).to receive(:start)
        subject.start
      end
    end

    describe '#block' do
      let(:callback) { instance_double(Proc, call: true) }
      let(:changes) do
        { modified: ['/foo'], added: [], removed: [] }
      end

      before do
        allow(broadcaster).to receive(:async).and_return async
      end

      after do
        subject.block.call changes.values
      end

      context 'when paused' do
        it 'honours paused state and does nothing' do
          subject.pause
          expect(broadcaster).not_to receive(:async)
          expect(callback).not_to receive(:call)
        end
      end

      context 'when stopped' do
        it 'honours stopped state and does nothing' do
          allow(subject).to receive(:supervisor) do
            instance_double(Celluloid::SupervisionGroup, terminate: true)
          end

          subject.stop
          expect(broadcaster).not_to receive(:async)
          expect(callback).not_to receive(:call)
        end
      end

      it 'broadcasts changes asynchronously' do
        message = Listen::TCP::Message.new changes
        expect(async).to receive(:broadcast).with message.payload
      end

      it 'invokes original callback block' do
        subject.block = callback
        expect(callback).to receive(:call).with(*changes.values)
      end
    end
  end

  context 'when recipient' do
    subject { described_class.new(port, :recipient) }

    it 'forces TCP adapter through options' do
      expect(subject.options).to include(force_tcp: true)
    end

    it { is_expected.not_to be_a_broadcaster }
    it { is_expected.to be_a_recipient }

    context 'when host is omitted' do
      describe '#host' do
        subject { super().host }
        it { is_expected.to eq described_class::DEFAULT_HOST }
      end
    end
  end

end
