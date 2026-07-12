#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <windows.h>

#include <queue>
#include <mutex>
#include <memory>
#include <string>

using namespace flutter;

template <typename T = EncodableValue>
class EventStreamHandler : public StreamHandler<T> {
 public:
  struct PendingEvent {
    enum class Kind { kSuccess, kError };

    Kind kind = Kind::kSuccess;
    std::unique_ptr<T> success_value;
    std::string error_code;
    std::string error_message;
    std::unique_ptr<T> error_details;

    static PendingEvent Success(std::unique_ptr<T> value) {
      PendingEvent event;
      event.kind = Kind::kSuccess;
      event.success_value = std::move(value);
      return event;
    }

    static PendingEvent Error(const std::string& code,
                             const std::string& message,
                             std::unique_ptr<T> details) {
      PendingEvent event;
      event.kind = Kind::kError;
      event.error_code = code;
      event.error_message = message;
      event.error_details = std::move(details);
      return event;
    }
  };

  class Bridge {
   public:
    void SetDispatchTarget(HWND hwnd, UINT message) {
      std::lock_guard<std::mutex> lock(m_mtx);
      m_hwnd = hwnd;
      m_message = message;
    }

    void Success(std::unique_ptr<T> value) {
      Enqueue(PendingEvent::Success(std::move(value)));
    }

    void Error(const std::string& code,
               const std::string& message,
               const T& details) {
      Enqueue(PendingEvent::Error(code, message, std::make_unique<T>(details)));
    }

    void Error(const std::string& code,
               const std::string& message,
               std::nullptr_t) {
      Enqueue(PendingEvent::Error(code, message, nullptr));
    }

    void Enqueue(PendingEvent event) {
      bool should_post = false;
      {
        std::lock_guard<std::mutex> lock(m_mtx);
        m_pending.emplace(std::move(event));
        should_post = m_hwnd != nullptr && m_message != 0;
      }

      if (should_post) {
        PostMessage(m_hwnd, m_message, 0, 0);
      }
    }

    void DrainPending() {
      std::queue<PendingEvent> pending;
      {
        std::lock_guard<std::mutex> lock(m_mtx);
        if (!m_sink) {
          return;
        }
        pending.swap(m_pending);
      }

      while (!pending.empty()) {
        auto event = std::move(pending.front());
        pending.pop();

        EventSink<T>* sink = nullptr;
        {
          std::lock_guard<std::mutex> lock(m_mtx);
          sink = m_sink.get();
        }
        if (!sink) {
          continue;
        }

        if (event.kind == PendingEvent::Kind::kSuccess) {
          if (event.success_value) {
            sink->Success(*event.success_value);
          }
        } else {
          sink->Error(event.error_code, event.error_message,
                      event.error_details ? *event.error_details : T{});
        }
      }
    }

    void SetSink(std::unique_ptr<EventSink<T>>&& sink) {
      std::lock_guard<std::mutex> lock(m_mtx);
      m_sink = std::move(sink);
    }

    void ClearSink() {
      std::lock_guard<std::mutex> lock(m_mtx);
      m_sink.reset();
      std::queue<PendingEvent>().swap(m_pending);
    }
  private:
    std::mutex m_mtx;
    HWND m_hwnd = nullptr;
    UINT m_message = 0;
    std::unique_ptr<EventSink<T>> m_sink;
    std::queue<PendingEvent> m_pending;
  };

  EventStreamHandler() : bridge_(std::make_shared<Bridge>()) {}

  virtual ~EventStreamHandler() = default;

  std::shared_ptr<Bridge> bridge() const { return bridge_; }

  void SetDispatchTarget(HWND hwnd, UINT message) {
    bridge_->SetDispatchTarget(hwnd, message);
  }

  void Success(std::unique_ptr<T> data) {
    bridge_->Enqueue(PendingEvent::Success(std::move(data)));
  }

  void Error(const std::string& error_code,
             const std::string& error_message,
             const T& error_details) {
    bridge_->Enqueue(PendingEvent::Error(
        error_code, error_message, std::make_unique<T>(error_details)));
  }

 protected:
    std::unique_ptr<StreamHandlerError<T>> OnListenInternal(
      const T* arguments,
      std::unique_ptr<EventSink<T>>&& events) override {
    bridge_->SetSink(std::move(events));
    bridge_->DrainPending();
    return nullptr;
  }

  std::unique_ptr<StreamHandlerError<T>> OnCancelInternal(
      const T* arguments) override {
    bridge_->ClearSink();
    return nullptr;
  }

 private:
  std::shared_ptr<Bridge> bridge_;
};
